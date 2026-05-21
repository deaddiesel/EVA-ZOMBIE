#pragma semicolon 1

#include <amxmodx>
#include <reapi>
#include <rezp>
#include <rezp_util>

const ADMINMENU_FLAGS = ADMIN_MENU;

public plugin_init()
{
	register_plugin("[ReZP] Menu: Admin", REZP_VERSION_STR, "fl0wer");

	new const cmds[][] = { "adminmenu", "say /adminmenu" };

	for (new i = 0; i < sizeof(cmds); i++)
		register_clcmd(cmds[i], "@Command_AdminMenu");

	register_menucmd(register_menuid("RZ_AdminMenu"), 1023, "@HandleMenu_Main");
}

@Command_AdminMenu(id)
{
	MainMenu_Show(id);
	return PLUGIN_HANDLED;
}

MainMenu_Show(id)
{
	if (!(get_user_flags(id) & ADMINMENU_FLAGS))
		return;

	new len;
	new text[MAX_MENU_LENGTH];

	new bool:warmup = rz_game_is_warmup();
	new bool:gameStarted = get_member_game(m_bGameStarted);
	new bool:freezePeriod = get_member_game(m_bFreezePeriod);
	new keys;

	SetGlobalTransTarget(id);

	add_formatex("\yАдмин-панель^n^n");

	add_formatex("\r1. \wВозродить игрока^n");
	keys |= MENU_KEY_1;

	if (!warmup && gameStarted && freezePeriod)
	{
		add_formatex("\r2. \wИзменить игровой режим^n");
		keys |= MENU_KEY_2;
	}
	else
		add_formatex("\d2. Изменить игровой режим^n");

	if (!warmup && gameStarted && !freezePeriod)
	{
		add_formatex("\r3. \wИзменить класс игрока^n");
		keys |= MENU_KEY_3;
	}
	else
		add_formatex("\d3. Изменить класс игрока^n");
	add_formatex("^n");
	add_formatex("^n");
	add_formatex("^n");
	add_formatex("^n");
	add_formatex("\r8. \wУправление игроками^n");
	keys |= MENU_KEY_8;

	add_formatex("\r9. \w%l", "RZ_BACK");
	keys |= MENU_KEY_9;

	add_formatex("^n\r0. \w%l", "RZ_CLOSE");
	keys |= MENU_KEY_0;

	show_menu(id, keys, text, -1, "RZ_AdminMenu");
}

@HandleMenu_Main(id, key)
{
	if (key == 9)
		return PLUGIN_HANDLED;
	
	if (!(get_user_flags(id) & ADMINMENU_FLAGS))
		return PLUGIN_HANDLED;

	switch (key)
	{
		case 0: amxclient_cmd(id, "respawnmenu");
		case 1: amxclient_cmd(id, "gamemodesmenu");
		case 2: amxclient_cmd(id, "changeclassmenu");
		
		case 7: // Клавиша 8
		{
			amxclient_cmd(id, "rz_supermenu_start");
		}
		
		case 8: // Клавиша 9
		{
			amxclient_cmd(id, "gamemenu");
		}
	}
	
	return PLUGIN_HANDLED;
}
