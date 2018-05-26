#include <sourcemod>
#include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <scp>
#include <colors>
#include <myjailbreak>

#pragma newdecls required

#define TRIGGER_SYMBOL2 '/'
#define SERVERADMINFLAG ADMFLAG_RESERVATION

//Global
char g_sBlockedTags[512][512];
int g_iBlockedTags = 0;
bool g_bEnabled = true;
int g_bPlusHP = 5;
int g_bPlusAR = 100;

ConVar g_hEnabled;
ConVar g_hHealth;
ConVar g_hArmor;
ConVar g_hPlusHP;
ConVar g_hPlusAR;
ConVar g_hPlusHE;
ConVar g_hRainbow;
ConVar g_hDeadRestrict;

//Cookies
Handle g_hVIPTag;
Handle g_hVIPClanTag;
Handle g_hVIPTagColor;
Handle g_hVIPNameColor;
Handle g_hVIPChatColor;
Handle g_hHealthState;
Handle g_hArmorState;
Handle g_hRainbowState;

//Client
bool g_sHealthState[MAXPLAYERS + 1];
bool g_sRainbowState[MAXPLAYERS + 1];
bool g_sArmorState[MAXPLAYERS + 1];
bool g_bIsClientVip[MAXPLAYERS + 1] = false;
bool g_sOnClanTagType[MAXPLAYERS + 1] = false;
bool g_sOnNameTagType[MAXPLAYERS + 1] = false;

char g_sTag[MAXPLAYERS + 1][128];
char g_sTagColor[MAXPLAYERS + 1][128];
char g_sClanTag[MAXPLAYERS + 1][128];
char g_sChatColor[MAXPLAYERS + 1][128];
char g_sNameColor[MAXPLAYERS + 1][128];

//Translations
char Prefix[32] = "\x01[\x04V.I.P.\x01] \x06";

public Plugin myinfo = 
{
	name = "[CSGO] Entity VIP System", 
	author = "Entity", 
	description = "VIP Features for CSGO", 
	version = "1.0"
};

public void OnPluginStart()
{
	LoadTranslations("entvip.phrases");

	g_hEnabled = CreateConVar("sm_entvip_enabled", "1", "Enable the vip system?", 0, true, 0.0, true, 1.0);
	g_hHealth = CreateConVar("sm_entvip_health", "1", "Allow vip players to use hp bonus?", 0, true, 0.0, true, 1.0);
	g_hArmor = CreateConVar("sm_entvip_armor", "1", "Allow vip players to use full armor bonus?", 0, true, 0.0, true, 1.0);
	g_hPlusHP = CreateConVar("sm_entvip_plushp", "5", "How much plus hp player gets?", 0, true, 0.0, true, 1000.0);
	g_hPlusAR = CreateConVar("sm_entvip_plusarmor", "100", "How much plus armor player gets?", 0, true, 0.0, true, 100.0);
	g_hPlusHE = CreateConVar("sm_entvip_plushelmet", "1", "Give Helmet with Armor?", 0, true, 0.0, true, 1.0);
	g_hRainbow = CreateConVar("sm_entvip_rainbowmodel", "1", "Allow vip players to use rainbow model?", 0, true, 0.0, true, 1.0);
	g_hDeadRestrict = CreateConVar("sm_entvip_deadrestrict", "0", "Restrict dead players to communicate with alive players? (JailBreak)", 0, true, 0.0, true, 1.0);
	
	g_hVIPTag = RegClientCookie("EntVipTags", "ENTVIP Tag", CookieAccess_Protected);
	g_hVIPClanTag = RegClientCookie("EntVipCTag", "ENTVIP ClanTag", CookieAccess_Protected);
	g_hVIPTagColor = RegClientCookie("EntVipTagColor", "ENTVIP TagColor", CookieAccess_Protected);
	g_hVIPNameColor = RegClientCookie("EntVipNameColor", "ENTVIP NameColor", CookieAccess_Protected);
	g_hVIPChatColor = RegClientCookie("EntVipChatColor", "ENTVIP ChatColor", CookieAccess_Protected);
	g_hHealthState = RegClientCookie("EntVipHealthState", "ENTVIP ChatColor", CookieAccess_Protected);
	g_hArmorState = RegClientCookie("EntVipArmorState", "ENTVIP ChatColor", CookieAccess_Protected);
	g_hRainbowState = RegClientCookie("EntVipRainbow", "ENTVIP Rainbow", CookieAccess_Protected);
	
	HookConVarChange(g_hEnabled, OnCvarChange_Enabled);
	HookConVarChange(g_hPlusHP, OnCvarChange_PlusHP);
	HookConVarChange(g_hPlusAR, OnCvarChange_PlusAR);
	
	AddCommandListener(OnMessageSent, "say");
	AddCommandListener(OnMessageSentTeam, "say_team");
	
	HookEvent("player_spawn", OnPlayerSpawn);
	
	RegAdminCmd("sm_vip", ShowVIPMenu, ADMFLAG_RESERVATION);
	BlackListAnalyze();
	
	AutoExecConfig(true, "entvip");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			PlayerInformations(i);
			if (IsValidClient(i) && GetConVarInt(g_hRainbow) && g_sRainbowState[i] == true)
			{
				SDKHook(i, SDKHook_PreThink, OnPlayerThink);
			}
			else
			{
				SDKUnhook(i, SDKHook_PreThink, OnPlayerThink);
				SetEntityRenderColor(i, 255, 255, 255, 255);
			}
		}
	}
}

public void OnMapStart()
{
	BlackListAnalyze();
}

public void OnClientPostAdminCheck(int client)
{
	CreateTimer(1.0, Timer_Analyze, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action OnPlayerSpawn(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	PlayerInformations(client);
	
	CreateTimer(0.3, Timer_CheckForEvent_HP, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	if (GetConVarInt(g_hHealth) == 1)
	{
		if (IsValidClient(client) && g_sHealthState[client] == true && g_bIsClientVip[client])
		{
			int cHealth = GetClientHealth(client);
			SetEntityHealth(client, cHealth + g_bPlusHP);
		}
	}
	if (GetConVarInt(g_hArmor) == 1)
	{
		if (IsValidClient(client) && g_sArmorState[client] == true && g_bIsClientVip[client])
		{
			SetEntProp(client, Prop_Send, "m_ArmorValue", GetConVarInt(g_hPlusAR), 1);
			if (GetConVarInt(g_hPlusHE) == 1)
			{
				SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
			}
		}
	}
	if (IsValidClient(client) && g_bIsClientVip[client])
	{
		CS_SetClientClanTag(client, g_sClanTag[client]);
	}
	if (IsValidClient(client) && GetConVarInt(g_hRainbow) && g_sRainbowState[client] == true)
	{
		SDKHook(client, SDKHook_PreThink, OnPlayerThink);
	}
	else
	{
		SDKUnhook(client, SDKHook_PreThink, OnPlayerThink); 
		SetEntityRenderColor(client, 255, 255, 255, 255);
	}
}

stock Action ShowVIPMenu(int client, int itemNum)
{
	if (GetConVarInt(g_hEnabled) == 1)
	{
		if (IsClientInGame(client))
		{
			if (g_bIsClientVip[client] == true)
			{
				Menu menu = CreateMenu(VipChoice);
				menu.SetTitle("VipMenu - By Entity");
				char HP[64], PHP[8];
				IntToString(g_bPlusHP, PHP, sizeof(PHP));
				if (GetConVarInt(g_hHealth) == 1)
				{
					if (g_sHealthState[client] == false)
					{
						Format(HP, sizeof(HP), "%t", "BonusHPON", PHP);
						menu.AddItem("health", HP);
					}
					else
					{
						Format(HP, sizeof(HP), "%t", "BonusHPOFF", PHP);
						menu.AddItem("health", HP);
					}
				}
				else
				{	
					Format(HP, sizeof(HP), "%t", "BonusHPDisabled");
					menu.AddItem("nothing", HP, ITEMDRAW_DISABLED);
				}
				char Armor[64], PAR[8];
				IntToString(g_bPlusAR, PAR, sizeof(PAR));
				if (GetConVarInt(g_hArmor) == 1)
				{
					if (g_sArmorState[client] == false)
					{
						Format(Armor, sizeof(Armor), "%t", "BonusArmorON", PAR);
						menu.AddItem("armor", Armor);
					}
					else
					{
						Format(Armor, sizeof(Armor), "%t", "BonusArmorOFF", PAR);
						menu.AddItem("armor", Armor);
					}
				}
				else
				{
					Format(Armor, sizeof(Armor), "%t", "BonusArmorDisabled");
					menu.AddItem("nothing", Armor, ITEMDRAW_DISABLED);
				}
				char tag[64], chat[64], rainbow[64];
				Format(tag, sizeof(tag), "%t", "ClanTagEditor");
				menu.AddItem("clantag", tag);
				Format(chat, sizeof(chat), "%t", "ChatMods");
				menu.AddItem("chatmod", chat);
				if (GetConVarInt(g_hRainbow) == 1)
				{
					if (g_sRainbowState[client] == false)
					{
						Format(rainbow, sizeof(rainbow), "%t", "RainbowOn");
						menu.AddItem("rainbow", rainbow);
					}
					else
					{
						Format(rainbow, sizeof(rainbow), "%t", "RainbowOff");
						menu.AddItem("rainbow", rainbow);
					}
				}
				else
				{
					Format(rainbow, sizeof(rainbow), "%t", "RainbowDisabled");
					menu.AddItem("nothing", rainbow, ITEMDRAW_DISABLED);
				}
				menu.Display(client, MENU_TIME_FOREVER);
			}
			else PrintToChat(client, "%s %t", Prefix, "OnlyVip");
		}
		else PrintToChat(client, "%s %t", Prefix, "OnlyInGame");
	}
	else PrintToChat(client, "%s %t", Prefix, "TurnedOff");
}

public int VipChoice(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			PrintToChat(client, "%s %t", Prefix, "TurnedOff");
			return;
		}
		
		char info[64];
		GetMenuItem(menu, itemNum, info, sizeof(info));
		if (StrEqual(info, "health"))
		{
			if (g_sHealthState[client] == false)
			{
				g_sHealthState[client] = true;
				SetClientCookie(client, g_hHealthState, "true");
				ShowVIPMenu(client, itemNum);
			}
			else
			{
				g_sHealthState[client] = false;
				SetClientCookie(client, g_hHealthState, "false");
				ShowVIPMenu(client, itemNum);
			}
		}
		if (StrEqual(info, "armor"))
		{
			if (g_sArmorState[client] == false)
			{
				g_sArmorState[client] = true;
				SetClientCookie(client, g_hArmorState, "true");
				ShowVIPMenu(client, itemNum);
			}
			else
			{
				g_sArmorState[client] = false;
				SetClientCookie(client, g_hArmorState, "false");
				ShowVIPMenu(client, itemNum);
			}
		}
		if (StrEqual(info, "chatmod"))
		{
			ShowNameTagMenu(client, 1);
		}
		if (StrEqual(info, "clantag"))
		{
			ShowClanTagMenu(client, 1);
		}
		if (StrEqual(info, "rainbow"))
		{
			if (g_sRainbowState[client] == true)
			{
				g_sRainbowState[client] = false;
				SetClientCookie(client, g_hRainbowState, "false");
				ShowVIPMenu(client, 1);
				SDKUnhook(client, SDKHook_PreThink, OnPlayerThink);
				SetEntityRenderColor(client, 255, 255, 255, 255);
				PrintToChat(client, "%s %t", Prefix, "RainbowDisabledMessage");
			}
			else
			{
				g_sRainbowState[client] = true;
				SetClientCookie(client, g_hRainbowState, "true");
				ShowVIPMenu(client, 1);
				SDKHook(client, SDKHook_PreThink, OnPlayerThink);
				PrintToChat(client, "%s %t", Prefix, "RainbowEnabledMessage");
			}
		}
	}
}

stock Action ShowNameTagMenu(int client, int itemNum)
{
	char edittag[128], tagcolor[128], namecolor[128], chatgcolor[128], removetag[128];
	Format(edittag, sizeof(edittag), "%t", "SetNameTag");
	Format(tagcolor, sizeof(tagcolor), "%t", "SetTagColor");
	Format(namecolor, sizeof(namecolor), "%t", "SetNameColor");
	Format(chatgcolor, sizeof(chatgcolor), "%t", "SetChatColor");
	Format(removetag, sizeof(removetag), "%t", "RemoveNameTag");
	
	Menu menu = CreateMenu(NameTagChoice);
	menu.SetTitle("ChatModifications - By Entity");
	menu.AddItem("edittag", edittag);
	menu.AddItem("tagcolor", tagcolor);
	menu.AddItem("namecolor", namecolor);
	menu.AddItem("chatgcolor", chatgcolor);
	if (!StrEqual(g_sTag[client], ""))
		menu.AddItem("removetag", removetag);
	else
		menu.AddItem("nothing", removetag, ITEMDRAW_DISABLED);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int NameTagChoice(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		GetMenuItem(menu, itemNum, info, sizeof(info));
		if (StrEqual(info, "edittag"))
		{
			g_sOnNameTagType[client] = true;
			ShowNameTagMenu(client, itemNum);
			PrintToChat(client, "%s %t", Prefix, "OnTypeNameTag")
		}
		if (StrEqual(info, "tagcolor"))
		{
			ColorMenu(client, 1, 1);
		}
		if (StrEqual(info, "namecolor"))
		{
			ColorMenu(client, 1, 2);
		}
		if (StrEqual(info, "chatgcolor"))
		{
			ColorMenu(client, 1, 3);
		}
		if (StrEqual(info, "removetag"))
		{
			Format(g_sTag[client], sizeof(g_sTag), "");
			SetClientCookie(client, g_hVIPTag, g_sTag[client]);
			PrintToChat(client, "%s %t", Prefix, "RemovedNameTag");
		}
	}
}

public Action ColorMenu(int client, int args, int MenuNum)
{
	char Default[64], SRed[64], Team[64], Green[64], Turquoise[64], Lime[64], LRed[64], LGray[64], Yellow[64], Gray[64], DBlue[64], Pink[64], Orange[64];
	Format(Default, sizeof(Default), "%t", "DefaultColor");
	Format(SRed, sizeof(SRed), "%t", "StrongRed");
	Format(Team, sizeof(Team), "%t", "TeamColor");
	Format(Green, sizeof(Green), "%t", "Green");
	Format(Turquoise, sizeof(Turquoise), "%t", "Turquoise");
	Format(Lime, sizeof(Lime), "%t", "Lime");
	Format(LRed, sizeof(LRed), "%t", "LightRed");
	Format(LGray, sizeof(LGray), "%t", "LightGray");
	Format(Yellow, sizeof(Yellow), "%t", "Yellow");
	Format(Gray, sizeof(Gray), "%t", "Gray");
	Format(DBlue, sizeof(DBlue), "%t", "DarkBlue");
	Format(Pink, sizeof(Pink), "%t", "Pink");
	Format(Orange, sizeof(Orange), "%t", "Orange");

	if (MenuNum == 1)
	{
		Menu menu = CreateMenu(TagMenu);
		menu.SetTitle("Choose Your Color");
		menu.AddItem("\x03", Default);
		menu.AddItem("\x02", SRed);
		menu.AddItem("\x03", Team);
		menu.AddItem("\x04", Green);
		menu.AddItem("\x05", Turquoise);
		menu.AddItem("\x06", Lime);
		menu.AddItem("\x07", LRed);
		menu.AddItem("\x08", LGray);
		menu.AddItem("\x09", Yellow);
		menu.AddItem("\x0A", Gray);
		menu.AddItem("\x0C", DBlue);
		menu.AddItem("\x0E", Pink);
		menu.AddItem("\x10", Orange);
		menu.Display(client, 30);
		return Plugin_Handled;
	}
	else if (MenuNum == 2)
	{
		Menu menu = CreateMenu(NameMenu);
		menu.SetTitle("Choose Your Color");
		menu.AddItem("\x03", Default);
		menu.AddItem("\x02", SRed);
		menu.AddItem("\x03", Team);
		menu.AddItem("\x04", Green);
		menu.AddItem("\x05", Turquoise);
		menu.AddItem("\x06", Lime);
		menu.AddItem("\x07", LRed);
		menu.AddItem("\x08", LGray);
		menu.AddItem("\x09", Yellow);
		menu.AddItem("\x0A", Gray);
		menu.AddItem("\x0C", DBlue);
		menu.AddItem("\x0E", Pink);
		menu.AddItem("\x10", Orange);
		menu.Display(client, 30);
		return Plugin_Handled;
	}
	else if (MenuNum == 3)
	{
		Menu menu = CreateMenu(ChatMenu);
		menu.SetTitle("Choose Your Color");
		menu.AddItem("\x03", Default);
		menu.AddItem("\x02", SRed);
		menu.AddItem("\x03", Team);
		menu.AddItem("\x04", Green);
		menu.AddItem("\x05", Turquoise);
		menu.AddItem("\x06", Lime);
		menu.AddItem("\x07", LRed);
		menu.AddItem("\x08", LGray);
		menu.AddItem("\x09", Yellow);
		menu.AddItem("\x0A", Gray);
		menu.AddItem("\x0C", DBlue);
		menu.AddItem("\x0E", Pink);
		menu.AddItem("\x10", Orange);
		menu.Display(client, 30);
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public int TagMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char info[64], sItemName[64];
		GetMenuItem(menu, itemNum, info, sizeof(info), _, sItemName, sizeof(sItemName));
		Format(g_sTagColor[client], sizeof(g_sTagColor), info);
		PrintToChat(client, "%s %t", Prefix, "ChangedTagColor", info, sItemName);
		SetClientCookie(client, g_hVIPTagColor, g_sTagColor[client]);
		menu.DisplayAt(client, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
}

public int NameMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char info[64], sItemName[64];
		GetMenuItem(menu, itemNum, info, sizeof(info), _, sItemName, sizeof(sItemName));
		Format(g_sNameColor[client], sizeof(g_sNameColor), info);
		PrintToChat(client, "%s %t", Prefix, "ChangedNameColor", info, sItemName);
		SetClientCookie(client, g_hVIPNameColor, g_sNameColor[client]);
		menu.DisplayAt(client, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
}

public int ChatMenu(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char info[64], sItemName[64];
		GetMenuItem(menu, itemNum, info, sizeof(info), _, sItemName, sizeof(sItemName));
		Format(g_sChatColor[client], sizeof(g_sChatColor), info);
		PrintToChat(client, "%s %t", Prefix, "ChangedChatColor", info, sItemName);
		SetClientCookie(client, g_hVIPChatColor, g_sChatColor[client]);
		menu.DisplayAt(client, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
}

stock Action ShowClanTagMenu(int client, int itemNum)
{
	char edittag[64], removetag[64];
	Format(edittag, sizeof(edittag), "%t", "ChangeClanTag");
	Format(removetag, sizeof(removetag), "%t", "RemoveClanTag");
	Menu menu = CreateMenu(ClanTagChoice);
	menu.SetTitle("ClanTagMenu - By Entity");
	menu.AddItem("edittag", edittag);
	if (!StrEqual(g_sClanTag[client], ""))
		menu.AddItem("removetag", removetag);
	else
		menu.AddItem("nothing", removetag, ITEMDRAW_DISABLED);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ClanTagChoice(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		GetMenuItem(menu, itemNum, info, sizeof(info));
		if (StrEqual(info, "edittag"))
		{
			g_sOnClanTagType[client] = true;
			ShowClanTagMenu(client, itemNum);
			PrintToChat(client, "%s %t", Prefix, "OnTypeClanTag");
		}
		if (StrEqual(info, "removetag"))
		{
			CS_SetClientClanTag(client, "");
			Format(g_sClanTag[client], sizeof(g_sClanTag), " ");
			SetClientCookie(client, g_hVIPClanTag, g_sClanTag[client]);
			PrintToChat(client, "%s %t", Prefix, "RemovedClanTag");
		}
	}
}

public Action OnMessageSent(int client, const char[] command, int args)
{
	char message[1024];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	if (g_sOnClanTagType[client])
	{
		if (StrEqual(message, "!cancel") || StrEqual(message, "/cancel"))
		{
			PrintToChat(client, "%s %t", Prefix, "TypeAborted");
			g_sOnClanTagType[client] = false;
		}
		else
		{
			bool block;
			for (int k = 0; k <= g_iBlockedTags; k++)
			{
				if (StrEqual(g_sBlockedTags[k], message, false))
				{
					block = true;
				}
			}
			if (block)
			{
				if (!CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC))
				{
					PrintToChat(client, "%s %t", Prefix, "NotAllowed");
					return Plugin_Handled;
				}
			}
			g_sOnClanTagType[client] = false;
			if (StrEqual(message, "none"))
			{
				Format(g_sClanTag[client], sizeof(g_sClanTag), "");
				CS_SetClientClanTag(client, "");
				PrintToChat(client, "%s %t", Prefix, "TagReset");
			}
			else
			{
				Format(g_sClanTag[client], sizeof(g_sClanTag), message);
				CS_SetClientClanTag(client, g_sClanTag[client]);
				PrintToChat(client, "%s %t", Prefix, "TagChanged", message);
			}
			SetClientCookie(client, g_hVIPClanTag, g_sClanTag[client]);
		}
		return Plugin_Handled;
	}
	if (g_sOnNameTagType[client])
	{
		if (StrEqual(message, "!cancel") || StrEqual(message, "/cancel"))
		{
			PrintToChat(client, "%s %t", Prefix, "TypeAborted");
			g_sOnNameTagType[client] = false;
		}
		else
		{
			bool block;
			for (int k = 0; k <= g_iBlockedTags; k++)
			{
				if (StrEqual(g_sBlockedTags[k], message, false))
				{
					block = true;
				}
			}
			if (block)
			{
				if (!CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC))
				{
					PrintToChat(client, "%s %t", Prefix, "NotAllowed");
					return Plugin_Handled;
				}
			}
			Format(g_sTag[client], sizeof(g_sTag), message);
			g_sOnNameTagType[client] = false;			
			if (StrEqual(message, "none"))
			{
				PrintToChat(client, "%s %t", Prefix, "TagReset");
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "TagChanged", message);
			}
			SetClientCookie(client, g_hVIPTag, g_sTag[client]);
		}
		return Plugin_Handled;
	}
	
	char arg[128];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArgString(message, sizeof(message));
	if (IsValidClient(client) && (g_bIsClientVip[client] == true) && arg[0] != '/')
	{			
		SendMessage(client, message, false);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnMessageSentTeam(int client, const char[] command, int args)
{
	char message[1024], arg[128];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArgString(message, sizeof(message));
	if (IsValidClient(client) && (g_bIsClientVip[client] == true) && arg[0] != '/')
	{		
		SendMessage(client, message, true);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

stock void SendMessage(int client, char h_strMessage[1024], bool teamchat)
{
	if (StrEqual(g_sTagColor[client], "")) g_sTagColor[client] = "\x06";
	if (StrEqual(g_sChatColor[client], "")) g_sChatColor[client] = "\x01";
	if (StrEqual(g_sNameColor[client], "")) g_sNameColor[client] = "\x06";
	if (StrEqual(g_sTag[client], "") || StrEqual(g_sTag[client], "none")) g_sTag[client] = "[V.I.P]";
	
	char name[MAX_NAME_LENGTH], chatMsg[1280];	
	GetClientName(client, name, sizeof(name));
	
	CRemoveTags(h_strMessage, sizeof(h_strMessage));
	StripQuotes(h_strMessage);

	Format(chatMsg, sizeof(chatMsg), "%s%s %s%s: %s%s", g_sTagColor[client], g_sTag[client], g_sNameColor[client], name, g_sChatColor[client], h_strMessage);

	if (teamchat)
	{
		int team = GetClientTeam(client);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
			{
				if (GetClientTeam(client) == 1)
				{
					CPrintToChatEx(i, client, "\x07%t %s", "Spec_Team", chatMsg);
				}
				else if (IsPlayerAlive(client))
				{
					CPrintToChatEx(i, client, "\x07%t %s", "Team", chatMsg);
				}
				else
				{
					CPrintToChatEx(i, client, "\x07%t%t %s", "Dead", "Team", chatMsg);
				}
			}
		}
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
			{
				if (GetClientTeam(client) == 1)
				{
					CPrintToChatEx(i, client, "\x07%t %s", "Spec", chatMsg);
				}
				else if (IsPlayerAlive(client))
				{
					CPrintToChatEx(i, client, "%s", chatMsg);
				}
				else
				{
					if (GetConVarInt(g_hDeadRestrict) == 1)
					{
						if (!IsPlayerAlive(i))
						{
							CPrintToChatEx(i, client, "\x07%t %s", "Dead", chatMsg);
						}
					}
					else
					{
						CPrintToChatEx(i, client, "\x07%t %s", "Dead", chatMsg);
					}
				}
			}
		}
	}
}

stock void BlackListAnalyze()
{
	char sPath[512];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/tagblacklist.txt");
	if (!FileExists(sPath))SetFailState("[ENTVIP] - Couldn't Find configs/tagblacklist.txt");
	KeyValues ReadConfig = new KeyValues("");
	ReadConfig.ImportFromFile(sPath);
	
	ReadConfig.JumpToKey("Blocked Tags");
	ReadConfig.GotoFirstSubKey();
	do {
		g_iBlockedTags++;
		ReadConfig.GetString("tag", g_sBlockedTags[g_iBlockedTags], sizeof(g_sBlockedTags));
	} while (ReadConfig.GotoNextKey());
}

stock bool IsValidClient(int client, bool alive = false, bool bots = false)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client) && (alive == false || IsPlayerAlive(client)) && (bots == false && !IsFakeClient(client)))
	{
		return true;
	}
	return false;
}

public void PlayerInformations(int client)
{
	if (IsClientInGame(client) && AreClientCookiesCached(client))
	{
		if (CheckCommandAccess(client, "sm_vip", ADMFLAG_RESERVATION)) g_bIsClientVip[client] = true;
		else g_bIsClientVip[client] = false;
		
		GetClientCookie(client, g_hVIPTag, g_sTag[client], sizeof(g_sTag));
		GetClientCookie(client, g_hVIPClanTag, g_sClanTag[client], sizeof(g_sClanTag));
		GetClientCookie(client, g_hVIPTagColor, g_sTagColor[client], sizeof(g_sTagColor));
		GetClientCookie(client, g_hVIPNameColor, g_sNameColor[client], sizeof(g_sNameColor));
		GetClientCookie(client, g_hVIPChatColor, g_sChatColor[client], sizeof(g_sChatColor));
		char tempo[8], tempt[8], templ[8];
		GetClientCookie(client, g_hHealthState, tempo, sizeof(tempo));
		if (StrEqual(tempo, "true")) g_sHealthState[client] = true; else g_sHealthState[client] = false;
		GetClientCookie(client, g_hArmorState, tempt, sizeof(tempt));
		if (StrEqual(tempt, "true")) g_sArmorState[client] = true; else g_sArmorState[client] = false;
		GetClientCookie(client, g_hRainbowState, templ, sizeof(templ));
		if (StrEqual(tempt, "true")) g_sRainbowState[client] = true; else g_sRainbowState[client] = false;
	}
}

public void OnCvarChange_Enabled(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if (StrEqual(newvalue, "1")) g_bEnabled = true;
	else if (StrEqual(newvalue, "0")) g_bEnabled = false;
}

public void OnCvarChange_PlusHP(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	g_bPlusHP = GetConVarInt(g_hPlusHP);
}

public void OnCvarChange_PlusAR(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	g_bPlusAR = GetConVarInt(g_hPlusAR);
}

public Action OnPlayerThink(int client)
{
	if (GetConVarInt(g_hRainbow) == 1)
	{
		if (IsValidClient(client))
		{
			float flRate = 1.0;
		
			int color[4];
			color[0] = RoundToNearest(Cosine((GetGameTime() * flRate) + client + 0) * 127.5 + 127.5);
			color[1] = RoundToNearest(Cosine((GetGameTime() * flRate) + client + 2) * 127.5 + 127.5);
			color[2] = RoundToNearest(Cosine((GetGameTime() * flRate) + client + 4) * 127.5 + 127.5);
			color[3] = 255;
			
			SetEntityRenderMode(client, RENDER_GLOW);
			SetEntityRenderColor(client, color[0], color[1], color[2], 255);
		}
	}
}

public Action Timer_CheckForEvent_HP(Handle timer, int client)
{
	if (IsValidClient(client))
	{
		int cHealth = GetClientHealth(client);
		if (MyJailbreak_IsEventDayPlanned() == true)
		{
			SetEntProp(client, Prop_Send, "m_ArmorValue", 0, 1);
			SetEntProp(client, Prop_Send, "m_bHasHelmet", 0);
			if (cHealth > 100)
			{
				SetEntityHealth(client, 100);
			}
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

public Action Timer_Analyze(Handle timer, int client)
{
	PlayerInformations(client);
	return Plugin_Continue;
}