#pragma semicolon 1

#include <amxmodx>
#include <reapi>
#include <hamsandwich>
#include <rezp>

#define PLUGIN "[ReZP] PySB Bots Integration"
#define VERSION "4.0_RELEASE"
#define AUTHOR "AI"

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	// Тотальная блокировка меню закупок для ботов, чтобы их ИИ не зацикливался
	RegisterHookChain(RG_CBasePlayer_HasRestrictItem, "@CBasePlayer_HasRestrictItem_Pre", false);
	
	register_clcmd("chooseteam", "@BlockBotMenu");
	register_clcmd("gamemenu", "@BlockBotMenu");
	
	// Хукаем пост-кадр оружия бота, чтобы намертво убрать фантомную тряску
	RegisterHam(Ham_Item_PostFrame, "weapon_knife", "@Ham_KnifePostFrame_Pre", false);
	
	// Ловим старт абсолютно любого режима RePlagueZ, чтобы пнуть застывших ботов на уровне физики движка
	register_forward(FM_CmdStart, "@CmdStart_Pre", false);
}

public client_putinserver(id)
{
	if (is_user_bot(id))
	{
		// 4 секунды задержки, чтобы все модули ядра успели создать структуры игрока
		set_task(4.0, "HandleBotJoin", id);
	}
}

public HandleBotJoin(id)
{
	if (!is_user_connected(id))
		return;

	new TeamName:team = TeamName:get_member(id, m_iTeam);

	if (team == TEAM_SPECTATOR || team == TEAM_UNASSIGNED)
	{
		new choice = random_num(1, 2);
		new TeamName:chosenTeam = (choice == 1) ? TEAM_CT : TEAM_TERRORIST;
		
		// Обнуляем триггеры коннекта и меню, пробивая ступор ИИ бота
		set_member(id, m_bJustConnected, false);
		set_member(id, m_iJoiningState, JOINED); 
		set_member(id, m_iMenu, Menu_ChooseTeam);
		
		// Закрываем текстовые AMXX меню старого формата
		show_menu(id, 0, "^n", 0); 

		// Выставляем команду
		set_member(id, m_iTeam, chosenTeam);
		rg_set_user_team(id, chosenTeam, MODEL_UNASSIGNED, true);
		
		// Выдаем легальный класс ядра RePlagueZ
		new defaultClass = rz_class_get_default(chosenTeam);
		if (defaultClass != -1)
		{
			rz_class_player_set(id, defaultClass);
		}

		set_member(id, m_bNotKilled, false);

		// Спавним
		rg_round_respawn(id);
		ExecuteHamB(Ham_Spawn, id);
		
		set_task(0.5, "WakeUpBotAI", id);
	}
}

public WakeUpBotAI(id)
{
	if (!is_user_connected(id)) return;
	
	client_cmd(id, "slot10"); // Сброс UI-окон для бота
	
	if (get_member(id, m_iTeam) == TEAM_TERRORIST)
	{
		rg_remove_all_items(id);
		rg_give_item(id, "weapon_knife");
		engclient_cmd(id, "weapon_knife"); // Жесткий приказ движку взять когти
	}
	
	// СИЛЬНЕЙШИЙ ПИНОК ДЛЯ ИИ SyPB:
	// Сбрасываем внутренний ступор ботов, отправляя им радиокоманду "Пошли"
	// Это заставляет ИИ SyPB пересчитать путь до ближайшей цели
	client_cmd(id, "radio1");
	client_cmd(id, "slot1");
}

@CmdStart_Pre(id, uc_handle, seed)
{
	if (!is_user_alive(id) || !is_user_bot(id))
		return FMRES_IGNORED;

	// Если раунд идет, а бот стоит на месте без кнопок движения (W, A, S, D)
	new buttons = get_uc(uc_handle, UC_Buttons);
	
	if (!(buttons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT)))
	{
		// Принудительно раз в несколько кадров симулируем для ИИ бота нажатие кнопки "Вперед"
		// Это выбивает ИИ SyPB из состояния «ложной заморозки» из-за кастомных пропсов мода
		if (random_num(1, 100) == 50)
		{
			buttons |= IN_FORWARD;
			set_uc(uc_handle, UC_Buttons, buttons);
		}
	}
	return FMRES_IGNORED;
}

@Ham_KnifePostFrame_Pre(item)
{
	new id = get_member(item, m_pPlayer);

	if (!is_user_connected(id) || !is_user_bot(id))
		return HAM_IGNORED;

	// УНИЧТОЖЕНИЕ ТРЯСКИ: Если бот — Зомби, мы каждую миллисекунду блокируем 
	// любые попытки его ИИ вызвать смену оружия или атаку огнестрелом
	if (get_member(id, m_iTeam) == TEAM_TERRORIST)
	{
		set_member(id, m_bCanShootOverride, false);
		
		// Если ИИ бота умудрился в этот кадр «спрятать» когти — силой возвращаем их через движок
		if (get_member(id, m_pActiveItem) != item)
		{
			engclient_cmd(id, "weapon_knife");
		}
	}
	return HAM_IGNORED;
}

@BlockBotMenu(id)
{
	if (is_user_bot(id))
	{
		return PLUGIN_HANDLED; // Запрещаем ботам даже трогать команды меню мода, чтобы они не слепли
	}
	return PLUGIN_CONTINUE;
}

@CBasePlayer_HasRestrictItem_Pre(id, ItemID:item, ItemRestType:type)
{
	if (!is_user_bot(id))
		return HC_CONTINUE;

	// Полный запрет на покупку чего-либо, выгружаем процессор бота из цикла закупки
	SetHookChainReturn(ATYPE_BOOL, true);
	return HC_SUPERCEDE;
}
