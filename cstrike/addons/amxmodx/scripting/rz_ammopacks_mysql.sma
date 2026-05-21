#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <rezp>
#include <sqlx>

#define PLUGIN_NAME    "[ReZP] MySQL Storage & Bank"
#define PLUGIN_VERSION "1.1.4"
#define PLUGIN_AUTHOR  "AI Developer"

new Handle:g_hTuple;
new bool:g_bPlayerLoaded[MAX_CLIENTS + 1];
new g_iRoundsPlayed[MAX_CLIENTS + 1];

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	
	register_event("HLTV", "@Event_RoundStart", "a", "1=0", "2=0");
	
	// Чат-команда для передачи денег между игроками
	register_clcmd("say /pay", "@Cmd_TransferMoney");
	register_clcmd("say_team /pay", "@Cmd_TransferMoney");
	
	// Админские консольные команды (Доступ по флагу L)
	register_concmd("amx_give_money", "@Cmd_AdminGiveMoney", ADMIN_RCON, "<target> <amount>");
	register_concmd("amx_take_money", "@Cmd_AdminTakeMoney", ADMIN_RCON, "<target> <amount>");
	register_concmd("amx_set_money", "@Cmd_AdminSetMoney", ADMIN_RCON, "<target> <amount>");
	
	SQL_Init();
}

public plugin_end()
{
	if (g_hTuple != Empty_Handle)
	{
		SQL_FreeHandle(g_hTuple);
	}
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
		set_fail_state("Failed to create database tuple");
		return;
	}
	
	new sQuery[32];
	formatex(sQuery, charsmax(sQuery), "SET NAMES utf8mb4");
	SQL_ThreadQuery(g_hTuple, "@Query_Ignore", sQuery);
}

public client_putinserver(id)
{
	if (is_user_hltv(id) || is_user_bot(id))
		return;
		
	g_bPlayerLoaded[id] = false;
	g_iRoundsPlayed[id] = 0;
	
	set_task(0.5, "@Task_LoadPlayer", id);
}

@Task_LoadPlayer(id)
{
	if (!is_user_connected(id))
		return;

	new sAuthID[32];
	get_user_authid(id, sAuthID, charsmax(sAuthID));
	
	if (equal(sAuthID, "VALVE_ID_PENDING") || equal(sAuthID, "STEAM_ID_PENDING"))
	{
		set_task(0.5, "@Task_LoadPlayer", id);
		return;
	}

	new sQuery[128];
	formatex(sQuery, charsmax(sQuery), "SELECT `money` FROM `eva_users` WHERE `steamid` = '%s';", sAuthID);
	
	new iData[1];
	iData[0] = get_user_userid(id);
	
	SQL_ThreadQuery(g_hTuple, "@Query_LoadData", sQuery, iData, sizeof(iData));
}

@Query_LoadData(iFailState, Handle:hQuery, sError[], iError, iData[], iSize, Float:fQueueTime)
{
	if (iFailState == TQUERY_CONNECT_FAILED || iFailState == TQUERY_QUERY_FAILED)
	{
		log_amx("SQL Error (%d): %s", iError, sError);
		return;
	}
	
	new id = find_player_by_userid(iData[0]);
	if (!id)
		return;
		
	new sAuthID[32];
	get_user_authid(id, sAuthID, charsmax(sAuthID));
	
	if (SQL_NumResults(hQuery) > 0)
	{
		new iMoney = SQL_ReadResult(hQuery, 0);
		set_member(id, m_iAccount, iMoney);
		g_bPlayerLoaded[id] = true;
		client_print(id, print_console, "[SQL] Успешно загружено %d аммо-паков из базы!", iMoney);
	}
	else
	{
		new sName[32], sEscapedName[64];
		get_user_name(id, sName, charsmax(sName));
		SQL_QuoteString(Empty_Handle, sEscapedName, charsmax(sEscapedName), sName);
		
		new iStartMoney = rz_main_ammopacks_join_amount();
		if (iStartMoney <= 0) iStartMoney = 500;
		
		set_member(id, m_iAccount, iStartMoney);
		
		new sQuery[256];
		formatex(sQuery, charsmax(sQuery), "INSERT INTO `eva_users` (`username`, `steamid`, `money`, `level`, `exp`) VALUES ('%s', '%s', '%d', '1', '0');", sEscapedName, sAuthID, iStartMoney);
		SQL_ThreadQuery(g_hTuple, "@Query_Ignore", sQuery);
		
		g_bPlayerLoaded[id] = true;
	}
}

public client_disconnected(id)
{
	if (!g_bPlayerLoaded[id] || is_user_bot(id) || is_user_hltv(id))
		return;
		
	Save_Player_Data(id);
	g_bPlayerLoaded[id] = false;
}

@Event_RoundStart()
{
	new iPlayers[MAX_CLIENTS], iNum, id;
	get_players(iPlayers, iNum, "ch");
	
	for (new i = 0; i < iNum; i++)
	{
		id = iPlayers[i];
		if (g_bPlayerLoaded[id])
		{
			g_iRoundsPlayed[id]++;
			if (g_iRoundsPlayed[id] % 3 == 0) 
			{
				Save_Player_Data(id);
			}
		}
	}
}

@Cmd_TransferMoney(id)
{
	if (!g_bPlayerLoaded[id])
		return PLUGIN_HANDLED;

	new sArg1[32], sArg2[16];
	read_argv(1, sArg1, charsmax(sArg1));
	read_argv(2, sArg2, charsmax(sArg2));
	
	if (!sArg1[0] || !sArg2[0])
	{
		client_print_color(id, print_team_default, "^4[Банк] ^1Использование: ^3/pay <ник> <сумма>");
		return PLUGIN_HANDLED;
	}
	
	new iTarget = cmd_target(id, sArg1, CMDTARGET_ALLOW_SELF);
	if (!iTarget || iTarget == id)
	{
		client_print_color(id, print_team_default, "^4[Банк] ^1Игрок не найден.");
		return PLUGIN_HANDLED;
	}
	
	new iAmount = str_to_num(sArg2);
	if (iAmount <= 0)
	{
		client_print_color(id, print_team_default, "^4[Банк] ^1Неверная сумма перевода.");
		return PLUGIN_HANDLED;
	}
	
	new iMyMoney = get_member(id, m_iAccount);
	if (iMyMoney < iAmount)
	{
		client_print_color(id, print_team_default, "^4[Банк] ^1У вас недостаточно средств.");
		return PLUGIN_HANDLED;
	}
	
	set_member(id, m_iAccount, iMyMoney - iAmount);
	set_member(iTarget, m_iAccount, get_member(iTarget, m_iAccount) + iAmount);
	
	Save_Player_Data(id);
	Save_Player_Data(iTarget);
	
	new sMyName[32], sTargetName[32];
	get_user_name(id, sMyName, charsmax(sMyName));
	get_user_name(iTarget, sTargetName, charsmax(sTargetName));
	
	client_print_color(id, print_team_default, "^4[Банк] ^1Вы перевели ^4%d ^1аммо игроку ^3%s^1.", iAmount, sTargetName);
	client_print_color(iTarget, print_team_default, "^4[Банк] ^1Игрок ^3%s ^1перевел вам ^4%d ^1аммо.", sMyName, iAmount);
	
	return PLUGIN_HANDLED;
}

@Cmd_AdminGiveMoney(id, level, cid)
{
	if (!cmd_access(id, level, cid, 3))
		return PLUGIN_HANDLED;
		
	new sTarget[32], sAmount[16];
	read_argv(1, sTarget, charsmax(sTarget));
	read_argv(2, sAmount, charsmax(sAmount));
	
	new iTarget = cmd_target(id, sTarget, CMDTARGET_OBEY_IMMUNITY);
	if (!iTarget) return PLUGIN_HANDLED;
	
	new iAmount = str_to_num(sAmount);
	set_member(iTarget, m_iAccount, get_member(iTarget, m_iAccount) + iAmount);
	Save_Player_Data(iTarget);
	
	console_print(id, "[SQL] Вы успешно выдали %d аммо игроку.", iAmount);
	return PLUGIN_HANDLED;
}

@Cmd_AdminTakeMoney(id, level, cid)
{
	if (!cmd_access(id, level, cid, 3))
		return PLUGIN_HANDLED;
		
	new sTarget[32], sAmount[16];
	read_argv(1, sTarget, charsmax(sTarget));
	read_argv(2, sAmount, charsmax(sAmount));
	
	new iTarget = cmd_target(id, sTarget, CMDTARGET_OBEY_IMMUNITY);
	if (!iTarget) return PLUGIN_HANDLED;
	
	new iAmount = str_to_num(sAmount);
	new iCurrent = get_member(iTarget, m_iAccount);
	set_member(iTarget, m_iAccount, (iCurrent - iAmount < 0) ? 0 : iCurrent - iAmount);
	Save_Player_Data(iTarget);
	
	console_print(id, "[SQL] Вы забрали %d аммо у игрока.", iAmount);
	return PLUGIN_HANDLED;
}

@Cmd_AdminSetMoney(id, level, cid)
{
	if (!cmd_access(id, level, cid, 3))
		return PLUGIN_HANDLED;
		
	new sTarget[32], sAmount[16];
	read_argv(1, sTarget, charsmax(sTarget));
	read_argv(2, sAmount, charsmax(sAmount));
	
	new iTarget = cmd_target(id, sTarget, CMDTARGET_OBEY_IMMUNITY);
	if (!iTarget) return PLUGIN_HANDLED;
	
	new iAmount = str_to_num(sAmount);
	set_member(iTarget, m_iAccount, iAmount);
	Save_Player_Data(iTarget);
	
	console_print(id, "[SQL] Вы установили баланс игрока на значение %d.", iAmount);
	return PLUGIN_HANDLED;
}

Save_Player_Data(id)
{
	if (!g_bPlayerLoaded[id])
		return;

	new sAuthID[32], sName[32], sEscapedName[64];
	get_user_authid(id, sAuthID, charsmax(sAuthID));
	get_user_name(id, sName, charsmax(sName));
	SQL_QuoteString(Empty_Handle, sEscapedName, charsmax(sEscapedName), sName);
	
	new iMoney = get_member(id, m_iAccount);
	
	new sQuery[256];
	formatex(sQuery, charsmax(sQuery), 
		"UPDATE `eva_users` SET `username` = '%s', `money` = '%d', `rounds_played` = `rounds_played` + %d WHERE `steamid` = '%s';", 
		sEscapedName, iMoney, g_iRoundsPlayed[id], sAuthID);
		
	SQL_ThreadQuery(g_hTuple, "@Query_Ignore", sQuery);
	g_iRoundsPlayed[id] = 0;
}

@Query_Ignore(iFailState, Handle:hQuery, sError[], iError, iData[], iSize, Float:fQueueTime)
{
	if (iFailState == TQUERY_CONNECT_FAILED || iFailState == TQUERY_QUERY_FAILED)
	{
		log_amx("SQL Save Error (%d): %s", iError, sError);
	}
}

find_player_by_userid(userid)
{
	new id = find_player("g", userid);
	return (id && get_user_userid(id) == userid) ? id : 0;
}
