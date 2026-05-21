#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <sqlx>

#if !defined T_SUCCESS
    #define T_SUCCESS 1
#endif

#pragma semicolon 1

new Handle:g_SqlTuple;

// Сетка времени (включая 1 месяц = 43200 минут)
new const TIMES[] = { 5, 30, 60, 1440, 10080, 43200, 0 };
new const TIMES_NAMES[][] = { "5 минут", "30 минут", "1 час", "1 день", "1 неделя", "1 месяц", "Навсегда" };

// 12 коротких причин бана под ZM
new const BAN_REASONS[][] = {
    "Читы / Софт", "Скрипты / Бхоп", "Сговор / Тимминг", "Блок / Застройка",
    "Анти-инфект", "Кач / Абуз", "Срыв игры", "Оскорбления",
    "Родные / Нации", "Флуд / Микро 18+", "Реклама / Спам", "Обход бана"
};

// 5 коротких причин мута
new const MUTE_REASONS[][] = {
    "Оскорбления / Мат",
    "Флуд / Мониторинг",
    "Микрофон 18+ / Писк",
    "Реклама / Спам",
    "Неадекватное поведение"
};

new g_TargetID[MAX_PLAYERS + 1], g_TargetTime[MAX_PLAYERS + 1];
new bool:g_IsMuted[MAX_PLAYERS + 1];

public plugin_init() {
    register_plugin("RZ SQL Ban & Mute", "2.5", "AI");
    
    // Команда вызова из plmenu.sma
    register_clcmd("rz_supermenu_start", "cmdStartMenu");
    
    // Блокировка чата
    register_clcmd("say", "hookSay");
    register_clcmd("say_team", "hookSay");
    
    // Блокировка микрофона
    register_forward(FM_Voice_SetClientListening, "fw_Voice_SetClientListening", 0);
}

public plugin_cfg() {
    new host[64], user[64], pass[64], db[64];
    get_cvar_string("amx_sql_host", host, charsmax(host));
    get_cvar_string("amx_sql_user", user, charsmax(user));
    get_cvar_string("amx_sql_pass", pass, charsmax(pass));
    get_cvar_string("amx_sql_db", db, charsmax(db));
    
    g_SqlTuple = SQL_MakeDbTuple(host, user, pass, db);
}

// Проверка бана и мута при заходе игрока
public client_authorized(id) {
    if(is_user_hltv(id) || is_user_bot(id)) return;
    
    g_IsMuted[id] = false;
    new authid[32], ip[32], query[512], data[1];
    get_user_authid(id, authid, charsmax(authid));
    get_user_ip(id, ip, charsmax(ip), 1);
    data[0] = get_user_userid(id);
    
    // Проверка бана (Используем IP и SteamID)
    formatex(query, charsmax(query), 
        "SELECT `ban_reason`, `ban_expired` FROM `eva_bans` WHERE (`player_steamid`='%s' OR `player_ip`='%s') AND `unbanned`='0' AND (`ban_expired` > '%d' OR `ban_length`='0') ORDER BY `id` DESC LIMIT 1;", 
        authid, ip, get_systime());
    SQL_ThreadQuery(g_SqlTuple, "CheckBanHandler", query, data, 1);
    
    // Проверка мута (Используем только SteamID строго по твоей БД)
    formatex(query, charsmax(query), 
        "SELECT `mute_expired` FROM `eva_mutes` WHERE `player_steamid`='%s' AND `unmuted`='0' AND (`mute_expired` > '%d' OR `mute_length`='0') ORDER BY `id` DESC LIMIT 1;", 
        authid, get_systime());
    SQL_ThreadQuery(g_SqlTuple, "CheckMuteHandler", query, data, 1);
}

public CheckBanHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    if(failstate != T_SUCCESS) return;
    if(SQL_NumResults(query) > 0) {
        new userid = data[0];
        new id = find_player("js", userid);
        if(id) {
            new reason[64], expired;
            SQL_ReadResult(query, 0, reason, charsmax(reason));
            expired = SQL_ReadResult(query, 1);
            new kick_msg[128];
            if(expired == 0) formatex(kick_msg, charsmax(kick_msg), "Вы забанены навсегда!^nПричина: %s", reason);
            else formatex(kick_msg, charsmax(kick_msg), "Вы забанены!^nОсталось: %d мин.^nПричина: %s", (expired - get_systime()) / 60, reason);
            server_cmd("kick #%d ^"%s^"", userid, kick_msg);
        }
    }
}

public CheckMuteHandler(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime) {
    if(failstate != T_SUCCESS) return;
    if(SQL_NumResults(query) > 0) {
        new id = find_player("js", data[0]);
        if(id) g_IsMuted[id] = true;
    }
}

// 1. Стартовое окно действий над игроком
public cmdStartMenu(id) {
    if(!(get_user_flags(id) & ADMIN_BAN)) return PLUGIN_HANDLED;
    
    new arg[16]; read_argv(1, arg, charsmax(arg));
    g_TargetID[id] = find_player("js", str_to_num(arg));
    if(!g_TargetID[id] || !is_user_connected(g_TargetID[id])) return PLUGIN_HANDLED;
    
    new t_name[32], menu_title[64]; 
    get_user_name(g_TargetID[id], t_name, charsmax(t_name));
    formatex(menu_title, charsmax(menu_title), "\y[Evangelion] Управление: \r%s", t_name);
    
    new menu = menu_create(menu_title, "menuActionHandler");
    menu_additem(menu, "\wЗабанить (БД)", "1");
    menu_additem(menu, "\wЗамутить (БД)", "2");
    menu_additem(menu, "\wКикнуть", "3");
    menu_additem(menu, "\wШлепнуть \d(Умный слэп)", "4");
    menu_additem(menu, "\wУбить \d(Slay)", "5");
    
    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public menuActionHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6]; menu_item_getinfo(menu, item, _, data, charsmax(data));
    new action = str_to_num(data);
    menu_destroy(menu);
    
    new target = g_TargetID[id];
    if(!is_user_connected(target)) return PLUGIN_HANDLED;
    
    new a_name[32], t_name[32];
    get_user_name(id, a_name, charsmax(a_name));
    get_user_name(target, t_name, charsmax(t_name));
    
    switch(action) {
        case 1: openTimeMenu(id, 1);
        case 2: openTimeMenu(id, 2);
        case 3: { // КИК
            if (get_user_flags(target) & ADMIN_IMMUNITY && !(get_user_flags(id) & ADMIN_RCON)) {
                client_print_color(id, print_team_default, "^4[Evangelion] ^1У игрока ^3Иммунитет^1! Вы не можете его кикнуть.");
                return PLUGIN_HANDLED;
            }
            client_print_color(0, print_team_default, "^4[Evangelion] ^3Админ ^4%s ^1кикнул игрока ^4%s^1.", a_name, t_name);
            server_cmd("kick #%d ^"Вы были кикнуты админом %s^"", get_user_userid(target), a_name);
        }
        case 4: { // СЛЭП
            new hp = get_user_health(target);
            new damage = (hp > 10) ? 5 : 0; 
            user_slap(target, damage);
            if (damage > 0) client_print_color(0, print_team_default, "^4[Evangelion] ^3Админ ^4%s ^1пнул игрока ^4%s ^1на ^35 HP^1.", a_name, t_name);
            else client_print_color(0, print_team_default, "^4[Evangelion] ^3Админ ^4%s ^1пнул игрока ^4%s ^5(Без урона, мало HP)^1.", a_name, t_name);
        }
        case 5: { // СЛЭЙ
            if (get_user_flags(target) & ADMIN_IMMUNITY && !(get_user_flags(id) & ADMIN_RCON)) {
                client_print_color(id, print_team_default, "^4[Evangelion] ^1У игрока ^3Иммунитет^1! Вы не можете его убить.");
                return PLUGIN_HANDLED;
            }
            user_kill(target);
            client_print_color(0, print_team_default, "^4[Evangelion] ^3Админ ^4%s ^1убил (Slay) игрока ^4%s^1.", a_name, t_name);
        }
    }
    return PLUGIN_HANDLED;
}

openTimeMenu(id, type) {
    new title[64]; formatex(title, charsmax(title), "\y[Evangelion] Выберите время (%s):", (type == 1) ? "Бан" : "Мут");
    new menu = menu_create(title, (type == 1) ? "menuBanTimeHandler" : "menuMuteTimeHandler");
    new item_num[3];
    for(new i = 0; i < sizeof(TIMES); i++) {
        num_to_str(i, item_num, charsmax(item_num));
        menu_additem(menu, TIMES_NAMES[i], item_num);
    }
    menu_display(id, menu, 0);
}

// 2. Обработчики времени и переход к причинам
public menuBanTimeHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6]; menu_item_getinfo(menu, item, _, data, charsmax(data));
    g_TargetTime[id] = str_to_num(data);
    menu_destroy(menu);
    
    new menu_ban = menu_create("\y[Evangelion] Причинаи бана:", "menuBanReasonHandler");
    new item_num[3];
    for(new i = 0; i < sizeof(BAN_REASONS); i++) {
        num_to_str(i, item_num, charsmax(item_num));
        menu_additem(menu_ban, BAN_REASONS[i], item_num);
    }
    menu_setprop(menu_ban, MPROP_NEXTNAME, "Далее");
    menu_setprop(menu_ban, MPROP_BACKNAME, "Назад");
    menu_setprop(menu_ban, MPROP_EXITNAME, "Выход");
    menu_display(id, menu_ban, 0);
    return PLUGIN_HANDLED;
}

public menuMuteTimeHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6]; menu_item_getinfo(menu, item, _, data, charsmax(data));
    g_TargetTime[id] = str_to_num(data);
    menu_destroy(menu);
    
    new menu_mute = menu_create("\y[Evangelion] Причина мута:", "menuMuteReasonHandler");
    new item_num[3];
    for(new i = 0; i < sizeof(MUTE_REASONS); i++) {
        num_to_str(i, item_num, charsmax(item_num));
        menu_additem(menu_mute, MUTE_REASONS[i], item_num);
    }
    menu_setprop(menu_mute, MPROP_BACKNAME, "Назад");
    menu_setprop(menu_mute, MPROP_EXITNAME, "Выход");
    menu_display(id, menu_mute, 0);
    return PLUGIN_HANDLED;
}

// 3. Финальная запись банов/мутов в БД
public menuBanReasonHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6]; menu_item_getinfo(menu, item, _, data, charsmax(data));
    new reason_idx = str_to_num(data);
    menu_destroy(menu);
    
    new target = g_TargetID[id];
    if(!is_user_connected(target)) return PLUGIN_HANDLED;
    
    new p_authid[32], p_name[32], p_ip[32], a_name[32];
    get_user_authid(target, p_authid, charsmax(p_authid));
    get_user_name(target, p_name, charsmax(p_name));
    get_user_ip(target, p_ip, charsmax(p_ip), 1);
    get_user_name(id, a_name, charsmax(a_name));
    
    new length = TIMES[g_TargetTime[id]];
    new created = get_systime();
    new expired = (length == 0) ? 0 : (created + (length * 60));
    
    new safe_p_name[64], safe_a_name[64], query[512];
    SQL_QuoteString(g_SqlTuple, safe_p_name, charsmax(safe_p_name), p_name);
    SQL_QuoteString(g_SqlTuple, safe_a_name, charsmax(safe_a_name), a_name);
    
    formatex(query, charsmax(query), 
        "INSERT INTO `eva_bans` (`player_steamid`, `player_name`, `player_ip`, `admin_name`, `ban_reason`, `ban_created`, `ban_length`, `ban_expired`, `unbanned`) \
        VALUES ('%s', '%s', '%s', '%s', '%s', '%d', '%d', '%d', '0');", 
        p_authid, safe_p_name, p_ip, safe_a_name, BAN_REASONS[reason_idx], created, length, expired);
    SQL_ThreadQuery(g_SqlTuple, "QueryHandlerDummy", query);
    
    client_print_color(0, print_team_default, "^4[Evangelion] ^3Админ ^4%s ^1забанил ^4%s ^1на ^3%s^1. Причина: ^4%s", a_name, p_name, TIMES_NAMES[g_TargetTime[id]], BAN_REASONS[reason_idx]);
    
    new kick_msg[128];
    formatex(kick_msg, charsmax(kick_msg), "Вы забанены! Причина: %s. Срок: %s", BAN_REASONS[reason_idx], TIMES_NAMES[g_TargetTime[id]]);
    server_cmd("kick #%d ^"%s^"", get_user_userid(target), kick_msg);
    return PLUGIN_HANDLED;
}

public menuMuteReasonHandler(id, menu, item) {
    if(item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[6]; menu_item_getinfo(menu, item, _, data, charsmax(data));
    new reason_idx = str_to_num(data);
    menu_destroy(menu);
    
    new target = g_TargetID[id];
    if(!is_user_connected(target)) return PLUGIN_HANDLED;
    
    new p_authid[32], p_name[32], a_name[32];
    get_user_authid(target, p_authid, charsmax(p_authid));
    get_user_name(target, p_name, charsmax(p_name));
    get_user_name(id, a_name, charsmax(a_name));
    
    new length = TIMES[g_TargetTime[id]];
    new created = get_systime();
    new expired = (length == 0) ? 0 : (created + (length * 60));
    
    new safe_p_name[64], safe_a_name[64], query[512];
    SQL_QuoteString(g_SqlTuple, safe_p_name, charsmax(safe_p_name), p_name);
    SQL_QuoteString(g_SqlTuple, safe_a_name, charsmax(safe_a_name), a_name);
    
    formatex(query, charsmax(query), 
        "INSERT INTO `eva_mutes` (`player_steamid`, `player_name`, `admin_name`, `mute_reason`, `mute_created`, `mute_length`, `mute_expired`, `unmuted`) \
        VALUES ('%s', '%s', '%s', '%s', '%d', '%d', '%d', '0');", 
        p_authid, safe_p_name, safe_a_name, MUTE_REASONS[reason_idx], created, length, expired);
    SQL_ThreadQuery(g_SqlTuple, "QueryHandlerDummy", query);
    
    g_IsMuted[target] = true;
    client_print_color(0, print_team_default, "^4[Evangelion] ^3Админ ^4%s ^1выдал мут ^4%s ^1на ^3%s^1. Причина: ^4%s", a_name, p_name, TIMES_NAMES[g_TargetTime[id]], MUTE_REASONS[reason_idx]);
    return PLUGIN_HANDLED;
}

// 4. Перехват и жесткое глушение чата + микрофона
public hookSay(id) {
    if(g_IsMuted[id]) {
        client_print_color(id, print_team_default, "^4[Evangelion] ^1У вас заблокирован чат!");
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public fw_Voice_SetClientListening(receiver, sender, bool:listen) {
    if(is_user_connected(sender) && g_IsMuted[sender]) {
        engfunc(EngFunc_SetClientListening, receiver, sender, false);
        return FMRES_SUPERCEDE; // Этого достаточно, чтобы намертво заглушить микрофон
    }
    return FMRES_IGNORED;
}

public QueryHandlerDummy(failstate, Handle:query, error[], errnum) {
    if(failstate != T_SUCCESS) log_amx("[SQL Error] %s (%d)", error, errnum);
}