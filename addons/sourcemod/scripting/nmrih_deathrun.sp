#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
//#include <autoexecconfig>

#define PLUGIN_AUTHOR "Ulreth*"
#define PLUGIN_VERSION "1.0.3" // 9-05-2024
#define PLUGIN_NAME "[NMRiH] Deathrun"

// MAP REQUIREMENTS:
/*
- Map name must contain 'deathrun'
- Traitor spawn location (info_target - "info_player_saw")
- Extraction start at round reset (only 1 objective)
*/

// CHANGELOG
/*
[1.0.0]
- First release

[1.0.1]
- Fixed wrong color showing up after round start

[1.0.2]
- Improved extraction method for traitor
- Updated map requirements for gamemode
- Fixed teleport bug for traitor
*/

#pragma semicolon 1
#pragma newdecls required

ConVar cVar_Deathrun_Enable;
ConVar cVar_Deathrun_Debug;

bool g_DeathrunMap = false;
Handle g_hTimer_Global = INVALID_HANDLE;

int g_PlayersCount = 0; // Alive player count
int g_PlayersArray[10] = {-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}; // Alive player array

float g_ExtractLocation[3] = {0.0, 0.0, 0.0};
float g_TraitorLocation[3] = {0.0, 0.0, 0.0};

int g_Traitor = -1; // Trap mastermind
char g_TraitorName[64];

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "This plugin will pick a random player every round start in objective game mode to be the enemy mastermind that can activate traps. Deathrun maps only",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/groups/lunreth-laboratory"
};

public void OnPluginStart()
{
	LoadTranslations("nmrih_deathrun.phrases");
	CreateConVar("sm_deathrun_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NONE);
	cVar_Deathrun_Enable = CreateConVar("sm_deathrun_enable", "1.0", "Enable or disable Deathrun plugin", FCVAR_NONE, true, 0.0, true, 1.0);
	cVar_Deathrun_Debug = CreateConVar("sm_deathrun_debug", "0.0", "Debug mode for plugin - Will spam messages in console if set to 1", FCVAR_NONE, true, 0.0, true, 1.0);
	AutoExecConfig(true, "nmrih_deathrun");
	
	HookEvent("nmrih_practice_ending", Event_PracticeStart);
	HookEvent("nmrih_reset_map", Event_ResetMap);
	HookEvent("nmrih_round_begin", Event_RoundBegin);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath);
	//HookEvent("player_leave", Event_PlayerLeave, EventHookMode_Pre);
	// PLUS OnMapStart()
	// PLUS OnTouch()
	// PLUS OnMapEnd()
	// PLUS OnClientDisconnect()
}

public void OnMapStart()
{
	char map[128];
	GetCurrentMap(map, sizeof(map));
	if (StrContains(map, "deathrun", false) != -1)
	{
		g_DeathrunMap = true;
		g_hTimer_Global = CreateTimer(9.0, Timer_Global, _, TIMER_REPEAT);
		
		int i = -1;
		while ((i = FindEntityByClassname(i, "info_target")) != -1)
		{
			char target_name[32];
			GetEntPropString(i, Prop_Data, "m_iName", target_name, sizeof(target_name));
			if (StrEqual(target_name, "info_player_saw", false))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", g_TraitorLocation);
			}
		}
		
		PrintToServer("[Deathrun] Deathrun map detected");
		LogMessage("[Deathrun] Deathrun map detected");
	}
}

public void OnMapEnd()
{
	delete g_hTimer_Global;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (PluginActive() == false) return;
	if (StrEqual(classname, "func_nmrih_extractionzone", false))
    {
		SDKHookEx(entity, SDKHook_StartTouch, OnTouch);
	}
}

public Action Event_PracticeStart(Event event, const char[] name, bool dontBroadcast)
{
	if (PluginActive() == true)
	{
		VariablesToZero();
		if (GetConVarFloat(cVar_Deathrun_Debug) == 1.0)
		{
			PrintToServer("[Deathrun] Variables set to zero.");
			LogMessage("[Deathrun] Variables set to zero.");
		}
	}
	return Plugin_Continue;
}

public Action Event_ResetMap(Event event, const char[] name, bool dontBroadcast)
{
	if (PluginActive() == true)
	{
		VariablesToZero();
		CreateTimer(0.5, Timer_CheckPlayers);
	}
	return Plugin_Continue;
}

public Action Timer_CheckPlayers(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && (GetClientTeam(i) == 0))
		{
			if (IsPlayerAlive(i)) AddToPlayerArray(i);
		}
	}
	if (g_PlayersCount >= 1) CreateTimer(1.0, Timer_PickTraitor);
	return Plugin_Continue;
}

public Action Timer_PickTraitor(Handle timer)
{
	// PICKS RANDOM g_Traitor FROM PLAYERS
	g_Traitor = RandomPlayer();
	if (g_Traitor > 0)
	{
		TeleportEntity(g_Traitor, g_TraitorLocation, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(g_Traitor, "glowable", "1"); 
		DispatchKeyValue(g_Traitor, "glowblip", "1");
		DispatchKeyValue(g_Traitor, "glowcolor", "255 0 0");
		DispatchKeyValue(g_Traitor, "glowdistance", "9999");
		AcceptEntityInput(g_Traitor, "enableglow");
		GetClientName(g_Traitor, g_TraitorName, sizeof(g_TraitorName));
		PrintToChatAll("[Deathrun] %t", "traitor_picked", g_TraitorName);
		PrintCenterTextAll("%t", "traitor_picked", g_TraitorName);
		if (GetConVarFloat(cVar_Deathrun_Debug) == 1.0)
		{
			PrintToServer("[Deathrun] %s is the traitor! Complete the deathrun to defeat him.", g_TraitorName);
			LogMessage("[Deathrun] %s is the traitor! Complete the deathrun to defeat him.", g_TraitorName);
		}
		PrintToChat(g_Traitor, "[Deathrun] %T", "traitor_private_message", g_Traitor);
	}
	return Plugin_Continue;
}

public Action Event_RoundBegin(Event event, const char[] name, bool dontBroadcast)
{
	if (PluginActive() == true)
	{
		if (g_Traitor > 0) PrintCenterText(g_Traitor, "%T", "traitor_center_message", g_Traitor);
	}
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (PluginActive() == true)
	{
		int userid = event.GetInt("userid");
		int client = GetClientOfUserId(userid);
		
		if(GetClientTeam(client) == 0) CreateTimer(0.5, Timer_TrueSpawn, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action Timer_TrueSpawn(Handle timer, any client)
{
	if(IsClientInGame(client))
	{
		if(IsPlayerAlive(client))
		{
			if (g_Traitor == client)
			{
				DispatchKeyValue(client, "glowable", "1"); 
				DispatchKeyValue(client, "glowblip", "1");
				DispatchKeyValue(client, "glowcolor", "255 0 0");
				DispatchKeyValue(client, "glowdistance", "9999");
				AcceptEntityInput(client, "enableglow");
				TeleportEntity(g_Traitor, g_TraitorLocation, NULL_VECTOR, NULL_VECTOR);
			}
			else AddToPlayerArray(client);
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (PluginActive() == true)
	{
		int userid = event.GetInt("userid");
		int client = GetClientOfUserId(userid);
		if (client != g_Traitor)
		{
			DeletePlayer(client);
			DispatchKeyValue(client, "glowable", "0"); 
			DispatchKeyValue(client, "glowblip", "0");
			DispatchKeyValue(client, "glowcolor", "80 201 255");
			DispatchKeyValue(client, "glowdistance", "9999");
			AcceptEntityInput(client, "disableglow");
		}
		else
		{
			CreateTimer(5.0, Timer_RespawnTraitor);
		}
		CheckTraitorWin();
	}
	return Plugin_Continue;
}

public Action Timer_RespawnTraitor(Handle timer)
{
	if (g_Traitor != -1)
	{
		RespawnClient(g_Traitor);
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	if (PluginActive() == true)
	{
		if ((g_Traitor > 0) && (client == g_Traitor))
		{
			// ROUND RESTARTING TO PICK NEW TRAITOR
			GetClientName(g_Traitor, g_TraitorName, sizeof(g_TraitorName));
			PrintToChatAll("[Deathrun] %t", "traitor_left", g_TraitorName);
			PrintCenterTextAll("%t", "traitor_restart", g_TraitorName);
			if (GetConVarFloat(cVar_Deathrun_Debug) == 1.0)
			{
				PrintToServer("[Deathrun] %s was the traitor and left the game! Restarting round in 10 seconds.", g_TraitorName);
				LogMessage("[Deathrun] %s was the traitor and left the game! Restarting round in 10 seconds.", g_TraitorName);
			}
			g_Traitor = -1;
			CreateTimer(10.0, Timer_EndRound);
		}
		DeletePlayer(client);
		//CheckTraitorWin();
	}
}
/*
public Action Event_PlayerLeave(Event event, const char[] name, bool dontBroadcast)
{
	if (PluginActive() == true)
	{
		int client = GetEventInt(event, "index");
		if ((g_Traitor > 0) && (client == g_Traitor))
		{
			// ROUND RESTARTING TO PICK NEW TRAITOR
			GetClientName(g_Traitor, g_TraitorName, sizeof(g_TraitorName));
			PrintToChatAll("[Deathrun] %t", "traitor_left", g_TraitorName);
			PrintCenterTextAll("%t", "traitor_restart", g_TraitorName);
			if (GetConVarFloat(cVar_Deathrun_Debug) == 1.0)
			{
				PrintToServer("[Deathrun] %s was the traitor and left the game! Restarting round in 30 seconds.", g_TraitorName);
				LogMessage("[Deathrun] %s was the traitor and left the game! Restarting round in 30 seconds.", g_TraitorName);
			}
			g_Traitor = -1;
			CreateTimer(30.0, Timer_EndRound);
		}
		DeletePlayer(client);
		//CheckTraitorWin();
	}
	return Plugin_Continue;
}
*/
public Action Timer_EndRound(Handle timer)
{
	if (g_PlayersCount > 0) EndRound();
	return Plugin_Continue;
}

public Action OnTouch(int entity, int client)
{
	if (PluginActive() == true)
	{
		char client_classname[64];
		GetEdictClassname(client, client_classname, 64);
		if (StrEqual(client_classname, "player", true))
		{
			// A SURVIVOR COMPLETED DEATHRUN
			if ((g_Traitor > 0) && (g_PlayersCount <= 2))
			{
				// ONLY TRAITOR REMAINS ALIVE
				if (IsPlayerAlive(g_Traitor))
				{
					ForcePlayerSuicide(g_Traitor);
					PrintToChatAll("[Deathrun] %t", "traitor_death", g_TraitorName);
					PrintCenterTextAll("%t", "traitor_death", g_TraitorName);
					if (GetConVarFloat(cVar_Deathrun_Debug) == 1.0)
					{
						PrintToServer("[Deathrun] Survivors win the round!");
						LogMessage("[Deathrun] Survivors win the round!");
					}
				}
				VariablesToZero();
			}
			DeletePlayer(client);
			DispatchKeyValue(client, "glowable", "0"); 
			DispatchKeyValue(client, "glowblip", "0");
			DispatchKeyValue(client, "glowcolor", "80 201 255");
			DispatchKeyValue(client, "glowdistance", "9999");
			AcceptEntityInput(client, "disableglow");
		}
	}
	return Plugin_Continue;
}

void VariablesToZero()
{
	g_Traitor = -1;
	g_PlayersCount = 0;
	for (int i = 0; i <= MaxClients; i++) g_PlayersArray[i] = -1;
}

bool PluginActive()
{
	bool answer = false;
	if ((g_DeathrunMap == true) && (GetConVarFloat(cVar_Deathrun_Enable) == 1.0))
	{
		answer = true;
	}
	return answer;
}

void AddToPlayerArray(int client)
{
	// Double check if was previously added
	g_PlayersArray[client] = client;
	g_PlayersCount = (g_PlayersCount + 1);
	
	DispatchKeyValue(client, "glowable", "1"); 
	DispatchKeyValue(client, "glowblip", "1");
	DispatchKeyValue(client, "glowcolor", "80 201 255");
	DispatchKeyValue(client, "glowdistance", "9999");
	AcceptEntityInput(client, "enableglow");
}

void DeletePlayer(int client)
{
	g_PlayersCount = (g_PlayersCount - 1);
	g_PlayersArray[client] = -1;
	if (g_Traitor == client) g_Traitor = -1;
	CheckTraitorWin();
}

int RandomPlayer()
{
	int random_client = -1;
	random_client = g_PlayersArray[GetRandomInt(1, g_PlayersCount)];
	return random_client;
}

int GetGameStateEntity()
{
	int nmrih_game_state = -1;
	while((nmrih_game_state = FindEntityByClassname(nmrih_game_state, "nmrih_game_state")) != -1)
		return nmrih_game_state;
	nmrih_game_state = CreateEntityByName("nmrih_game_state");
	if(IsValidEntity(nmrih_game_state) && DispatchSpawn(nmrih_game_state))
		return nmrih_game_state;
	return -1;
}

bool RespawnClient(int client)
{
	int state = GetGameStateEntity();
	if(IsValidEntity(state)){
		SetVariantString("!activator");
		return AcceptEntityInput(state, "RespawnPlayer", client);
	}
	return false;
}

bool EndRound()
{
	int state = GetGameStateEntity();
	if(IsValidEntity(state))
		return AcceptEntityInput(state, "RestartRound");
	return false;
}

void CheckTraitorWin()
{
	if ((g_PlayersCount <= 1) && (g_Traitor > 0))
	{
		int player_count = 0;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i)) player_count++;
		}
		if ((IsPlayerAlive(g_Traitor)) && (player_count > 1))
		{
			PrintToChatAll("[Deathrun] %t", "traitor_extracted", g_TraitorName);
			PrintCenterTextAll("%t", "traitor_extracted", g_TraitorName);
			if (GetConVarFloat(cVar_Deathrun_Debug) == 1.0)
			{
				PrintToServer("[Deathrun] %s wins the round!", g_TraitorName);
				LogMessage("[Deathrun] %s wins the round!", g_TraitorName);
			}
		}
		CreateTimer(2.0, Timer_TraitorWin, g_Traitor);
	}
}

public Action Timer_TraitorWin(Handle timer)
{
	if (g_Traitor > 0)
	{
		ServerCommand("extractplayer %d", GetClientUserId(g_Traitor));
		/*
		int j = -1;
		while ((j = FindEntityByClassname(j, "func_nmrih_extractionzone")) != -1)
		{
			if (IsValidEntity(j))
			{
				GetEntPropVector(j, Prop_Data, "m_vecOrigin", g_ExtractLocation);
			}
		}
		TeleportEntity(g_Traitor, g_ExtractLocation, NULL_VECTOR, NULL_VECTOR);
		*/
	}
	VariablesToZero();
	return Plugin_Continue;
}

public Action Timer_Global(Handle timer)
{
	if (g_Traitor != -1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				if (i != g_Traitor)
				{
					PrintHintText(i, "[Deathrun] %T", "traitor_all_hud", i, g_TraitorName);
					if (IsPlayerAlive(i)) DispatchKeyValue(i, "glowcolor", "80 200 255");
				}
				else
				{
					PrintHintText(i, "[Deathrun] %T", "traitor_indicator", i);
					if (IsPlayerAlive(i)) DispatchKeyValue(i, "glowcolor", "255 0 0");
				}
			}
		}
	}
	return Plugin_Continue;
}