#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <sqlx>

#define PLUGIN_NAME    "[ReZP] MySQL Chat Prefixes"
#define PLUGIN_VERSION "2.2.0"
#define PLUGIN_AUTHOR  "AI Developer"

enum _:GroupStruct
{
	Group_Flags[32],
	Group_Prefix[32],
	Group_Color[10]
};

new Array:g_aChatGroups;
new Handle:g_hTuple;

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	
	g_aChatGroups = ArrayCreate(GroupStruct, 0);
	
	register_clcmd("say", "@Cmd_HookSay");
	register_clcmd("say_team", "@Cmd_HookSay");
	
	SQL_Init();
}

public plugin_end()
{
	if (g_hTuple != Empty_Handle)
		SQL_FreeHandle(g_hTuple);
		
	if (g_aChatGroups != Invalid_Array)
		ArrayDestroy(g_aChatGroups);
}

SQL_Init()
{
	new sHost[64], sUser[64], sPass[64], sDB[64], sTimeout[16];
	
	get_cvar_string("amx_sql_host", sHost, charsmax(sHost));
	get_cvar_string("amx_sql_user", sUser, charsmax(sUser));
	get_cvar_string("amx_sql_pass", sPass, charsmax(sPass));
	get_cvar_string("amx_sql_db", sDB, charsmax(sDB));
	get_cvar_string("amx_sql_timeout", sTimeout, charsmax(sTimeout));
	
	g_hTuple = SQL_MakeDbTuple(sHost, sUser, sPass, sDB, str_to_num(sTimeout));
	
	if (g_hTuple == Empty_Handle)
	{
		log_amx("[ReZP Prefixes] Ошибка создания Tuple для MySQL");
		return;
	}
	
	SQL_SetCharset(g_hTuple, "utf8mb4");
	
	new sQuery[256];
	formatex(sQuery, charsmax(sQuery), "SELECT `amxx_flags`, `chat_prefix`, `chat_color` FROM `eva_groups` WHERE `chat_prefix` != '' ORDER BY `id` ASC;");
	SQL_ThreadQuery(g_hTuple, "@Query_LoadPrefixes", sQuery);
}

@Query_LoadPrefixes(iFailState, Handle:hQuery, sError[], iError, iData[], iSize, Float:fQueueTime)
{
	if (iFailState == TQUERY_CONNECT_FAILED || iFailState == TQUERY_QUERY_FAILED)
	{
		log_amx("[ReZP Prefixes] SQL Error (%d): %s", iError, sError);
		return;
	}
	
	ArrayClear(g_aChatGroups);
	
	new data[GroupStruct];
	while (SQL_MoreResults(hQuery))
	{
		SQL_ReadResult(hQuery, 0, data[Group_Flags], charsmax(data[Group_Flags]));
		SQL_ReadResult(hQuery, 1, data[Group_Prefix], charsmax(data[Group_Prefix]));
		SQL_ReadResult(hQuery, 2, data[Group_Color], charsmax(data[Group_Color]));
		
		ArrayPushArray(g_aChatGroups, data);
		SQL_NextRow(hQuery);
	}
	
	log_amx("[ReZP Prefixes] Успешно загружено %d префиксов из MySQL базы!", ArraySize(g_aChatGroups));
}

@Cmd_HookSay(id)
{
	if (!is_user_connected(id) || ArraySize(g_aChatGroups) == 0)
		return PLUGIN_CONTINUE;

	new sArgs[190];
	read_args(sArgs, charsmax(sArgs));
	remove_quotes(sArgs);
	trim(sArgs);

	if (!sArgs[0] || sArgs[0] == '/')
		return PLUGIN_CONTINUE;

	new iUserFlags = get_user_flags(id);
	new data[GroupStruct];
	new bool:bFound = false;

	for (new i = 0; i < ArraySize(g_aChatGroups); i++)
	{
		ArrayGetArray(g_aChatGroups, i, data);
		
		new iRequiredFlags = read_flags(data[Group_Flags]);
		
		if ((iUserFlags & iRequiredFlags) == iRequiredFlags || (iRequiredFlags & ADMIN_RCON && iUserFlags & ADMIN_RCON))
		{
			bFound = true;
			break;
		}
	}

	if (!bFound)
		return PLUGIN_CONTINUE;

	new sName[32];
	get_user_name(id, sName, charsmax(sName));

	new sCmd[16];
	read_argv(0, sCmd, charsmax(sCmd));
	
	new iTeamChat = equal(sCmd, "say_team");
	new iAlive = is_user_alive(id);
	
	new sMyTeam[16];
	get_user_info(id, "team", sMyTeam, charsmax(sMyTeam));

	new sFormatedColor[4];
	// Посимвольная проверка первого знака кодировки цвета из базы
	if (data[Group_Color][1] == '4' || data[Group_Color][0] == '4')      formatex(sFormatedColor, charsmax(sFormatedColor), "^4");
	else if (data[Group_Color][1] == '3' || data[Group_Color][0] == '3') formatex(sFormatedColor, charsmax(sFormatedColor), "^3");
	else if (data[Group_Color][1] == '2' || data[Group_Color][0] == '2') formatex(sFormatedColor, charsmax(sFormatedColor), "^2");
	else                                                                 formatex(sFormatedColor, charsmax(sFormatedColor), "^1");

	new sFullMessage[190];
	formatex(sFullMessage, charsmax(sFullMessage), "%s%s ^3%s^1 :  %s", sFormatedColor, data[Group_Prefix], sName, sArgs);

	new iPlayers[32], iNum, iTarget;
	get_players(iPlayers, iNum, "ch");

	new sTargetTeam[16];
	for (new i = 0; i < iNum; i++)
	{
		iTarget = iPlayers[i];

		if (iAlive != is_user_alive(iTarget))
			continue;

		if (iTeamChat)
		{
			get_user_info(iTarget, "team", sTargetTeam, charsmax(sTargetTeam));
			if (!equal(sMyTeam, sTargetTeam))
				continue;
		}

		client_print_color(iTarget, id, sFullMessage);
	}

	return PLUGIN_HANDLED;
}
