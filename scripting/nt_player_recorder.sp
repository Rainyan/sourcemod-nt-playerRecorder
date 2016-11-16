#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <neotokyo>

#define PLUGIN_VERSION "0.1"
//#define DEBUG

enum {
	PREF_WHOLE_MAPS = 1,
	PREF_HIGHLIGHTS,
	PREF_ALL_ROUNDS,
	PREF_ENUM_COUNT
};

enum {
	PANEL_CHOICE_RECORD = 1,
	PANEL_CHOICE_MODE,
	PANEL_CHOICE_CRITERIA,
	PANEL_CHOICE_ENUM_COUNT
};

#define DEFAULT_PREFERENCE PREF_WHOLE_MAPS
#define MENU_TIME 20
#define HIGHLIGHT_THRESHOLD_DEFAULT 4

// TODO: translation phrases
char g_sPrefWholeMaps[] = "Record whole maps";
char g_sPrefHighlights[] = "Record highlights (experimental)";
char g_sPrefAllRounds[] = "Record each round separately";
char g_sTag[] = "[REC]";

new const String:g_sMenuSoundOK[] = "buttons/button14.wav";
new const String:g_sMenuSoundCancel[] = "buttons/combine_button7.wav";

char g_sRandomID[MAXPLAYERS+1][10];
char g_sReplayFile[MAXPLAYERS+1][100];

bool g_bIsEditingXPThreshold[MAXPLAYERS+1];
bool g_bIsRecording[MAXPLAYERS+1];

int g_iClientTotalXP[MAXPLAYERS+1] = 0;
int g_iHighlightXPThreshold[MAXPLAYERS+1];
int g_iPreference[MAXPLAYERS+1];
int g_iRoundCount;

public Plugin myinfo =
{
	name = "Neotokyo Player Recorder",
	author = "Rain",
	description = "Clientside demo replay recorder",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-playerRecorder"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_rec", Panel_Record_Main, "Toggle client demo recording plugin");
	RegConsoleCmd("sm_record", Panel_Record_Main, "Toggle client demo recording plugin");
	HookEvent("game_round_start", Event_RoundStart);
}

public void OnClientDisconnect(int client)
{
	// FIXME !!! It's not in time, need some other way

	// Stop recording, so the game doesn't autoincrement filenames.
	// This would mess up map names in file names etc.
	ClientCommand(client, "stop");

	g_iClientTotalXP[client] = 0;
	g_iHighlightXPThreshold[client] = 0;
	g_iPreference[client] = 0;

	g_bIsEditingXPThreshold[client] = false;
	g_bIsRecording[client] = false;
}

public void OnMapEnd()
{
	g_iRoundCount = 0;
}

public Action Event_RoundStart(Handle event, const char[] Name, bool dontBroadcast)
{
	if (g_iRoundCount > 0)
	{
		g_iRoundCount++;
	}
	// Deduce round count from team scores if plugin was loaded mid game.
	// This ignores ties but gives some context for replay naming.
	else
	{
		g_iRoundCount += GetTeamScore(TEAM_JINRAI) + GetTeamScore(TEAM_NSF);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bIsRecording[i] || !IsValidClient(i) || IsFakeClient(i))
			continue;

		if (g_iPreference[i] == PREF_ALL_ROUNDS || g_iPreference[i] == PREF_HIGHLIGHTS)
		{
			StartRecord(i);
		}
	}
}

void StartRecord(int client)
{
	if (!IsValidClient(client))
	{
		ThrowError("%s Invalid client %i attempted to StartRecord()", g_sTag, client);
	}
	if (!g_bIsRecording[client])
	{
		ThrowError("%s Client %i reached StartRecord() even though \
g_bIsRecording[client] = false", g_sTag, client);
	}

	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));

	char time[18];
	FormatTime(time, sizeof(time), "%Y-%m-%d_%H-%M");

	GenerateRandomID(client);

	char commandBuffer[25 + sizeof(time) + sizeof(mapName) + sizeof(g_iRoundCount) + sizeof(g_sRandomID)];

	switch (g_iPreference[client])
	{
		// Record every round separately
		case PREF_ALL_ROUNDS:
		{
			if (g_iRoundCount < 1)
			{
				Format(commandBuffer, sizeof(commandBuffer),
					"record auto_%s_%s_warmup", time, mapName);
			}
			else
			{
				Format(commandBuffer, sizeof(commandBuffer),
					"record auto_%s_%s_round-%i", time, mapName, g_iRoundCount);
			}
			strcopy(g_sReplayFile[client], sizeof(g_sReplayFile), commandBuffer);
		}
		// Record whole maps
		case PREF_WHOLE_MAPS:
		{
			Format(commandBuffer, sizeof(commandBuffer),
				"record auto_%s_%s_%s", time, mapName, g_sRandomID[client]);
			strcopy(g_sReplayFile[client], sizeof(g_sReplayFile), commandBuffer);
		}
		// Record only highlights, overwrite "boring" stuff
		// by using the same record name. Experimental.
		case PREF_HIGHLIGHTS:
		{
			int gainedXP = GetEntProp(client, Prop_Data, "m_iFrags") - g_iClientTotalXP[client];
			if (gainedXP >= g_iHighlightXPThreshold[client] ||
					strlen(g_sReplayFile[client]) < 1)
			{
				Format(commandBuffer, sizeof(commandBuffer), "record auto_%s_%s_%s",
					time, mapName, g_sRandomID[client]);
				strcopy(g_sReplayFile[client], sizeof(g_sReplayFile), commandBuffer);
			}
			else
			{
				PrintToConsole(client, "%s Got %i XP last round while threshold is %i. \
Overwriting %s.dem.",
g_sTag, gainedXP, g_iHighlightXPThreshold[client], g_sReplayFile[client]);
			}
			g_iClientTotalXP[client] += gainedXP;
		}
	}

#if defined DEBUG
		PrintToServer("%s Recording to %s.dem...", g_sTag, g_sReplayFile[client]);
		PrintToChat(client, "Started new record");
		PrintToConsole(client, "Command: %s", commandBuffer);
#else
		// Stop possible previous recording.
		// This does nothing if there wasn't a recording running.
		ClientCommand(client, "stop");
		// Start new recording.
		ClientCommand(client, commandBuffer);
#endif
}

public Action Panel_Record_Main(int client, int args)
{
	Handle panel = CreatePanel();
	SetPanelTitle(panel, "Automatic Round Recorder");
	DrawPanelText(panel, " ");

	if (g_iPreference[client] == 0)
		g_iPreference[client] = DEFAULT_PREFERENCE;

	char prefBuffer[128];
	if (g_iPreference[client] == PREF_WHOLE_MAPS)
	{
		Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_sPrefWholeMaps);
	}
	else if (g_iPreference[client] == PREF_HIGHLIGHTS)
	{
		Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_sPrefHighlights);
	}
	else if (g_iPreference[client] == PREF_ALL_ROUNDS)
	{
		Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_sPrefAllRounds);
	}
	else
	{
		CloseHandle(panel);
		ReplyToCommand(client, "%s Something went wrong, perhaps poke your admin.", g_sTag);
		ThrowError("Invalid g_iPreference %i, cannot start recording.", g_iPreference[client]);
	}

	if (g_bIsRecording[client])
	{
		char buffer[128];
		Format(buffer, sizeof(buffer), "Currently recording: %s.dem", g_sReplayFile[client]);

		DrawPanelText(panel, buffer);
		DrawPanelText(panel, prefBuffer);
		DrawPanelText(panel, " ");
		DrawPanelItem(panel, "Stop recording");
	}
	else
	{
		DrawPanelText(panel, "Not recording.");
		DrawPanelText(panel, prefBuffer);
		DrawPanelText(panel, " ");
		DrawPanelItem(panel, "Start recording");
	}

	DrawPanelItem(panel, "Edit recording behaviour");
	DrawPanelItem(panel, "Edit highlight mode criteria");
	DrawPanelItem(panel, "Exit");

	SendPanelToClient(panel, client, PanelHandler_Main, MENU_TIME);
	CloseHandle(panel);

	return Plugin_Handled;
}

public PanelHandler_Main(Handle menu, MenuAction action, int client, int choice)
{
	if (action != MenuAction_Select)
		return;

	if (choice < PANEL_CHOICE_ENUM_COUNT)
	{
		Command_ConfigureRecord(client, choice);
		PrecacheSound(g_sMenuSoundOK);
		EmitSoundToClient(client, g_sMenuSoundOK);
	}
	// Exit
	else
	{
		PrecacheSound(g_sMenuSoundCancel);
		EmitSoundToClient(client, g_sMenuSoundCancel);
	}
}

public PanelHandler_Preferences(Handle menu, MenuAction action, int client, int choice)
{
	if (action != MenuAction_Select)
		return;

	// Edit preference
	if (choice == 1)
	{
		Handle panel = CreatePanel();
		SetPanelTitle(panel, "Edit preference");

		DrawPanelText(panel, " ");
		DrawPanelItem(panel, g_sPrefWholeMaps);
		DrawPanelItem(panel, g_sPrefHighlights);
		DrawPanelItem(panel, g_sPrefAllRounds);
		DrawPanelItem(panel, "Back");

		SendPanelToClient(panel, client, PanelHandler_Preferences_Edit, MENU_TIME);
		CloseHandle(panel);

		PrecacheSound(g_sMenuSoundOK);
		EmitSoundToClient(client, g_sMenuSoundOK);
	}
	// Go back
	else
	{
		Panel_Record_Main(client, 2);
		PrecacheSound(g_sMenuSoundCancel);
		EmitSoundToClient(client, g_sMenuSoundCancel);
	}
}

public PanelHandler_Preferences_Edit(Handle menu, MenuAction action, int client, int choice)
{
	if (action != MenuAction_Select)
		return;

	if (choice > PREF_ENUM_COUNT)
	{
		PrecacheSound(g_sMenuSoundCancel);
		EmitSoundToClient(client, g_sMenuSoundCancel);
	}
	else
	{
		g_iPreference[client] = choice;
		PrecacheSound(g_sMenuSoundOK);
		EmitSoundToClient(client, g_sMenuSoundOK);
	}

	Command_ConfigureRecord(client, PANEL_CHOICE_MODE);
}

public PanelHandler_HighlightCriteria(Handle menu, MenuAction action, int client, int choice)
{
	if (action != MenuAction_Select)
		return;

	if (choice == 1)
	{
		PrintToChat(client, "%s Please type the XP threshold in the chat. \
Type \"cancel\" to cancel.", g_sTag);
		g_bIsEditingXPThreshold[client] = true;
		AddCommandListener(SayCallback_XPThreshold, "say");
		AddCommandListener(SayCallback_XPThreshold, "say_team");

		PrecacheSound(g_sMenuSoundOK);
		EmitSoundToClient(client, g_sMenuSoundOK);
		return;
	}
	// Back to main menu.
	PrecacheSound(g_sMenuSoundCancel);
	EmitSoundToClient(client, g_sMenuSoundCancel);
	Panel_Record_Main(client, 1);
}

public Action SayCallback_XPThreshold(int client, const char[] command, int argc)
{
	if (!g_bIsEditingXPThreshold[client])
		return Plugin_Continue;

	decl String:message[256];
	GetCmdArgString(message, sizeof(message));

	StripQuotes(message);
	TrimString(message);

	if (Contains(message, "cancel"))
	{
		PrintToChat(client, "%s Cancelled editing the XP threshold.", g_sTag);
		RemoveCommandListener(SayCallback_XPThreshold, "say");
		RemoveCommandListener(SayCallback_XPThreshold, "say_team");
		g_bIsEditingXPThreshold[client] = false;
		return Plugin_Stop;
	}

	int threshold = StringToInt(message);
	if (threshold < 0)
	{
		PrintToChat(client, "%s Please insert a positive integer value.", g_sTag);
		PrintToChat(client, "Type \"cancel\" to stop editing the threshold.");
		return Plugin_Stop;
	}

	g_iHighlightXPThreshold[client] = threshold;
	g_bIsEditingXPThreshold[client] = false;

	RemoveCommandListener(SayCallback_XPThreshold, "say");
	RemoveCommandListener(SayCallback_XPThreshold, "say_team");

	PrintToChat(client, "%s Threshold has been changed to %i XP.", g_sTag, threshold);

	Command_ConfigureRecord(client, 3); // Draw the XP edit panel again.
	return Plugin_Stop;
}

void Command_ConfigureRecord(int client, int choice)
{
	switch (choice)
	{
		case PANEL_CHOICE_RECORD:
		{
			if (g_bIsRecording[client])
			{
				ClientCommand(client, "stop");
				PrintToChat(client, "%s Stopped recording.", g_sTag);
				g_bIsRecording[client] = false;
				Panel_Record_Main(client, 1);
			}
			else
			{
				g_bIsRecording[client] = true;
				StartRecord(client);
				Panel_Record_Main(client, 2);
			}
		}

		case PANEL_CHOICE_MODE:
		{
			Handle panel = CreatePanel();
			SetPanelTitle(panel, "Recording preferences");
			DrawPanelText(panel, " ");

			char prefBuffer[128];
			if (g_iPreference[client] == PREF_WHOLE_MAPS)
			{
				Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_sPrefWholeMaps);
			}
			else if (g_iPreference[client] == PREF_HIGHLIGHTS)
			{
				Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_sPrefHighlights);
			}
			else
			{
				Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_sPrefAllRounds);
			}

			DrawPanelText(panel, prefBuffer);
			DrawPanelText(panel, " ");
			DrawPanelItem(panel, "Change behaviour");
			DrawPanelItem(panel, "Back");

			SendPanelToClient(panel, client, PanelHandler_Preferences, MENU_TIME);
			CloseHandle(panel);
		}

		case PANEL_CHOICE_CRITERIA:
		{
			Handle panel = CreatePanel();
			SetPanelTitle(panel, "Edit highlight mode criteria");
			DrawPanelText(panel, " ");

			char buffer[128];
			Format(buffer, sizeof(buffer), "Current threshold for keeping a round replay: %i XP", g_iHighlightXPThreshold[client]);
			DrawPanelText(panel, buffer);
			DrawPanelText(panel, " ");
			DrawPanelItem(panel, "Edit XP threshold for saving a round replay");
			DrawPanelItem(panel, "Back");

			SendPanelToClient(panel, client, PanelHandler_HighlightCriteria, MENU_TIME);
			CloseHandle(panel);
		}
	}
}

void GenerateRandomID(int client)
{
	char alphanumeric[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
	int length = strlen(alphanumeric);

	// Concatenate a random character from the array one at a time
	int i;
	for (i = 0; i < 10; i++)
	{
		int randomIndex = GetRandomInt(0, length - 1);
		g_sRandomID[client][i] = alphanumeric[randomIndex];
	}
	g_sRandomID[client][i] = 0;
}

bool Contains(const char[] haystack, const char[] needle)
{
	if (StrContains(haystack, needle, false) != -1)
		return true;

	return false;
}
