#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "0.1"

enum {
	PREF_WHOLE_MAPS = 1,
	PREF_HIGHLIGHTS,
	PREF_ALL_ROUNDS
};

enum {
	PANEL_CHOICE_RECORD = 1,
	PANEL_CHOICE_MODE,
	PANEL_CHOICE_CRITERIA,
	PANEL_CHOICE_HELP
};

#define HIGHLIGHT_THRESHOLD_DEFAULT 4

// Global strings we use in a bunch of menus
char g_prefWholeMaps[] = "Record whole maps";
char g_prefHighlights[] = "Record highlights (experimental)";
char g_prefAllRounds[] = "Record each round separately";
char g_divider[] = "=====";
char g_tag[] = "RECORD";
char g_githubUrl[] = "https://github.com/Rainyan/sourcemod-nt-playerRecorder";

// Button sounds
char g_menuSoundOk[] = "buttons/button14.wav";
char g_menuSoundCancel[] = "buttons/combine_button7.wav";

// Some other globals for replay file generation
char g_randomID[MAXPLAYERS+1][10];
char g_replayFile[MAXPLAYERS+1][100];

// Global booleans
bool debugMode = false;
bool IsRecording[MAXPLAYERS+1];
bool IsEditingXPThreshold[MAXPLAYERS+1];

// Global integers
int clientTotalXP[MAXPLAYERS+1] = 0;
int highlightXPThreshold[MAXPLAYERS+1] = 4; // Default XP threshold for the highlights mode
int roundCount;
int g_preference[MAXPLAYERS+1] = PREF_ALL_ROUNDS;

public Plugin myinfo =
{
	name = "Neotokyo Player Recorder",
	author = "Rain",
	description = "Clientside demo replay recorder",
	version = PLUGIN_VERSION,
	url = g_githubUrl
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_record", Panel_Record_Main, "Record");
	HookEvent("game_round_start", Event_RoundStart);
}

bool Contains(const char[] haystack, const char[] needle)
{
	if (StrContains(haystack, needle, false) != -1)
		return true;

	return false;
}

bool IsValidClient(int client)
{
	if (client != 0 && IsClientConnected(client) && !IsFakeClient(client))
		return true;

	return false;
}

public Action Event_RoundStart(Handle event, const char[] Name, bool dontBroadcast)
{
	if (roundCount != 0)
	{
		roundCount++;
	}
	else // Deduce round count from team scores, in case we got loaded mid game. This ignores ties but oh well.
	{
		roundCount += GetTeamScore(2) + GetTeamScore(3);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsRecording[i])
			continue;

		if (g_preference[i] == PREF_ALL_ROUNDS || g_preference[i] == PREF_HIGHLIGHTS)
		{
			StartRecord(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	if (IsRecording[client])
	{
		StartRecord(client);
	}

	else
	{
		highlightXPThreshold[client] = HIGHLIGHT_THRESHOLD_DEFAULT;
	}
}

public void OnMapEnd()
{
	roundCount = 0;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		if (IsRecording[i])
			ClientCommand(i, "stop"); // Stop recording, so the game doesn't autoincrement filenames (this would mess up map names in file names etc.)
	}
}

public Action StartRecord(int client)
{
	if (!IsValidClient(client))
	{
		LogError("[%s] Invalid client %i attempted to StartRecord()", g_tag, client);
		return Plugin_Stop;
	}

	if (!IsRecording[client])
	{
		LogError("[%s] Client %i reached StartRecord() even though IsRecording[client] = false", g_tag, client);
		return Plugin_Stop;
	}

	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));

	char date[11];
	FormatTime(date, sizeof(date), "%Y-%m-%d");

	char time[6];
	FormatTime(time, sizeof(time), "%H-%M");

	GenerateRandomID(client);

	char commandBuffer[26 + sizeof(date) + sizeof(time) + sizeof(mapName) + sizeof(roundCount) + sizeof(g_randomID)];

	if (g_preference[client] == PREF_ALL_ROUNDS) // Record every round separately
	{
		if (roundCount < 1)
			Format(commandBuffer, sizeof(commandBuffer), "record auto_%s_time-%s_%s_warmup", date, time, mapName);

		else
			Format(commandBuffer, sizeof(commandBuffer), "record auto_%s_time-%s_%s_round-%i", date, time, mapName, roundCount);

		ReplaceString(commandBuffer, sizeof(commandBuffer), "record ", "");
		strcopy(g_replayFile[client], sizeof(g_replayFile), commandBuffer);
	}

	else if (g_preference[client] == PREF_WHOLE_MAPS) // Record whole maps
	{
		Format(commandBuffer, sizeof(commandBuffer), "record auto_%s_%s_%s", date, mapName, g_randomID[client]);
		strcopy(g_replayFile[client], sizeof(g_replayFile), commandBuffer);
	}

	else // Record only highlights, overwrite "boring" stuff by using the same record name. Experimental.
	{
		int gainedXP = GetEntProp(client, Prop_Data, "m_iFrags") - clientTotalXP[client];

		if (gainedXP >= highlightXPThreshold[client] || strlen(g_replayFile[client]) < 1)
		{
			Format(commandBuffer, sizeof(commandBuffer), "record auto_%s_%s_%s", date, mapName, g_randomID[client]);
			strcopy(g_replayFile[client], sizeof(g_replayFile), commandBuffer);
		}

		else
		{
			PrintToConsole(client, "[%s] Got %i XP last round while threshold is %i. Overwriting %s.dem.", g_tag, gainedXP, highlightXPThreshold[client], g_replayFile[client]);
		}

		clientTotalXP[client] += gainedXP;
	}

	//PrintToChat(client, "[%s] Recording to %s.dem...", g_tag, g_replayFile[client]); // debug
	//PrintToConsole(client, "[%s] Recording to %s.dem...", g_tag, g_replayFile[client]); // debug

	if (debugMode)
	{
		PrintToChat(client, "Record: %s", commandBuffer); // Debug
		PrintToConsole(client, "Command: %s", commandBuffer); // Debug
	}

	if (!debugMode)
	{
		ClientCommand(client, "stop"); // Stop possible previous recording. Does nothing if there wasn't a recording running.
		ClientCommand(client, commandBuffer); // Start new recording.

		PrintToChat(client, "Started new record"); // Debug
		PrintToConsole(client, "Command: %s", commandBuffer); // Debug
	}

	return Plugin_Handled;
}

public Action Panel_Record_Main(int client, int args)
{
	/*
	// jic switch if all goes to hell
	if (!IsValidAdmin(client))
	{
		PrintToChat(client, "[SM] Sorry, this is a work in progress, and doesn't work properly yet. Access limited for now.");
		return Plugin_Stop;
	}
	*/

	Handle panel = CreatePanel();
	SetPanelTitle(panel, "Automatic Round Recorder");

	DrawPanelText(panel, " ");

	char prefBuffer[128];
	if (g_preference[client] == PREF_WHOLE_MAPS)
		Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_prefWholeMaps);

	else if (g_preference[client] == PREF_HIGHLIGHTS)
		Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_prefHighlights);

	else
		Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_prefAllRounds);

	if (IsRecording[client])
	{
		new String:buffer[128];
		Format(buffer, sizeof(buffer), "Currently recording: %s.dem", g_replayFile[client]);

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

	DrawPanelItem(panel, "Help");

	DrawPanelItem(panel, "Exit");

	SendPanelToClient(panel, client, PanelHandler_Main, 20);

	CloseHandle(panel);

	return Plugin_Handled;
}

public Action Panel_Record_Help(int client, int choice)
{
	Handle panel = CreatePanel();

	if (choice == 1) // "What does this plugin do?"
	{
		SetPanelTitle(panel, "What does this plugin do?");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "This plugin will automatically record your gameplay");
		DrawPanelText(panel, "into Source replay files. These files are");
		DrawPanelText(panel, "relatively small and have a minimal impact on");
		DrawPanelText(panel, "game performance.");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "You can also manually record these files with");
		DrawPanelText(panel, "the console command \"record filename\", but");
		DrawPanelText(panel, "this plugin will take care of that for you,");
		DrawPanelText(panel, "including naming the replays descriptively.");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "You can access the replay player by pressing");
		DrawPanelText(panel, "Shift+F2 in Neotokyo.");
		/* This won't fit, need multi page panel if we want to include it.
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "The .dem replay files themselves are located at");
		DrawPanelText(panel, "Steam/SteamApps/common/NEOTOKYO/NeotokyoSource.");
		*/
	}

	else if (choice == 2) // "How does the highlights mode work?"
	{
		SetPanelTitle(panel, "How does the highlights mode work?");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "The highlights mode is experimental.");
		DrawPanelText(panel, "It tries to only save the interesting rounds.");
		DrawPanelText(panel, "Currently, it only takes the gained XP in count.");
		DrawPanelText(panel, "You probably want to use the \"record whole maps\"");
		DrawPanelText(panel, "mode instead, if you're worried about losing good");
		DrawPanelText(panel, "replays.");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "If you have suggestions on improving the");
		DrawPanelText(panel, "algorithm, please poke Rain.");
	}

	else if (choice == 3) // "I have a feature request!"
	{
		SetPanelTitle(panel, "I have a feature request! I found a bug!");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "This plugin is open source. You can contribute at:");
		DrawPanelText(panel, g_githubUrl);
		PrintToConsole(client, "%s\n[%s] Auto recorder project url: %s", g_divider, g_tag, g_githubUrl);

		Handle serverIP = FindConVar("hostip");
		char serverIPBuffer[128];
		GetConVarString(serverIP, serverIPBuffer, sizeof(serverIPBuffer));

		if (!Contains(serverIPBuffer, "108.61.116.38"))
		{
			DrawPanelText(panel, "You can also directly send suggestions to Rain:");
			DrawPanelText(panel, "http://steamcommunity.com/id/uminari");
			PrintToConsole(client, "[%s] Rain's profile url: http://steamcommunity.com/id/uminari\n%s", g_tag, g_divider);
			DrawPanelText(panel, "These urls were also copied to your console for your convenience.");
		}

		else // We're at Rain's server, so we can just advertise the !feedback command instead
		{
			DrawPanelText(panel, "You can also send suggestions by typing");
			DrawPanelText(panel, "!feedback, followed by your ideas on this");
			DrawPanelText(panel, "server's chat.");
		}

		CloseHandle(serverIP);
	}

	else if (choice == 4) // "Where can I get this plugin?"
	{
		SetPanelTitle(panel, "Where can I get this plugin?");
		DrawPanelText(panel, " ");
		DrawPanelText(panel, "This plugin is open source. If you're a server operator,");
		DrawPanelText(panel, "you can find the source code at:");
		DrawPanelText(panel, g_githubUrl);
		PrintToConsole(client, "%s\n[%s] Auto recorder project url: %s\n%s", g_divider, g_tag, g_githubUrl, g_divider);
		DrawPanelText(panel, "The url was also copied to your console for your convenience.");
	}

	DrawPanelText(panel, " ");
	DrawPanelItem(panel, "Back");

	SendPanelToClient(panel, client, PanelHandler_Help_Explanation, 120);
	CloseHandle(panel);

	return Plugin_Handled;
}

public PanelHandler_Help_Explanation(Handle menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		EmitSoundToClient(client, g_menuSoundCancel);
		Command_ConfigureRecord(client, PANEL_CHOICE_HELP);
	}
}

public PanelHandler_Main(Handle menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		if (choice < 5)
		{
			EmitSoundToClient(client, g_menuSoundOk);
			Command_ConfigureRecord(client, choice);
		}

		else // Exit
			EmitSoundToClient(client, g_menuSoundCancel);
	}
}

public PanelHandler_Preferences(Handle menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		if (choice == 1) // Edit preference
		{
			EmitSoundToClient(client, g_menuSoundOk);

			Handle panel = CreatePanel();
			SetPanelTitle(panel, "Edit preference");

			DrawPanelText(panel, " ");
			DrawPanelItem(panel, g_prefWholeMaps);
			DrawPanelItem(panel, g_prefHighlights);
			DrawPanelItem(panel, g_prefAllRounds);
			DrawPanelItem(panel, "Back");

			SendPanelToClient(panel, client, PanelHandler_Preferences_Edit, 20);

			CloseHandle(panel);
		}

		else // Go back
		{
			EmitSoundToClient(client, g_menuSoundCancel);
			Panel_Record_Main(client, 2);
		}
	}
}

public PanelHandler_Preferences_Edit(Handle menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		if (choice == 1) // Record whole maps
		{
			g_preference[client] = PREF_WHOLE_MAPS;
		}

		else if (choice == 2) // Record highlights
		{
			g_preference[client] = PREF_HIGHLIGHTS;
		}

		else if (choice == 3) // Record rounds separately
		{
			g_preference[client] = PREF_ALL_ROUNDS;
		}

		if (choice < 4)
			EmitSoundToClient(client, g_menuSoundOk);

		else // Go back
			EmitSoundToClient(client, g_menuSoundCancel);

		Command_ConfigureRecord(client, PANEL_CHOICE_MODE);
	}
}

public PanelHandler_Help(Handle menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		if (choice < 5) // Selection other than "back"
		{
			EmitSoundToClient(client, g_menuSoundOk);
			Panel_Record_Help(client, choice);
		}

		else // Go back
		{
			EmitSoundToClient(client, g_menuSoundCancel);
			Panel_Record_Main(client, 1);
		}
	}
}

public PanelHandler_HighlightCriteria(Handle menu, MenuAction action, int client, int choice)
{
	if (action == MenuAction_Select)
	{
		if (choice == 1)
		{
			EmitSoundToClient(client, g_menuSoundOk);
			PrintToChat(client, "[%s] Please type the XP threshold in the chat. Type \"cancel\" to cancel.", g_tag);
			IsEditingXPThreshold[client] = true;
			AddCommandListener(SayCallback_XPThreshold, "say");
			AddCommandListener(SayCallback_XPThreshold, "say_team");
		}

		else
		{
			EmitSoundToClient(client, g_menuSoundCancel);
			Panel_Record_Main(client, 1); // Back to main menu.
		}
	}
}

public Action SayCallback_XPThreshold(int client, const char[] command, int argc)
{
	if (!IsEditingXPThreshold[client])
		return Plugin_Continue;

	decl String:message[256];
	GetCmdArgString(message, sizeof(message));

	StripQuotes(message);
	TrimString(message);

	if (Contains(message, "cancel"))
	{
		PrintToChat(client, "[%s] Cancelled editing the XP threshold.", g_tag);
		RemoveCommandListener(SayCallback_XPThreshold, "say");
		RemoveCommandListener(SayCallback_XPThreshold, "say_team");
		IsEditingXPThreshold[client] = false;
		return Plugin_Stop;
	}

	int threshold = StringToInt(message);

	if (threshold < 0)
	{
		PrintToChat(client, "[%s] Please insert a positive integer value.", g_tag);
		PrintToChat(client, "Type \"cancel\" to stop editing the threshold.");
		return Plugin_Stop;
	}

	highlightXPThreshold[client] = threshold;

	IsEditingXPThreshold[client] = false;

	RemoveCommandListener(SayCallback_XPThreshold, "say");
	RemoveCommandListener(SayCallback_XPThreshold, "say_team");

	PrintToChat(client, "[%s] Threshold has been changed to %i XP.", g_tag, threshold);

	Command_ConfigureRecord(client, 3); // Draw the XP edit panel again.

	return Plugin_Stop;
}

public Action Command_ConfigureRecord(int client, int choice)
{
	if (choice == 1) // Toggle recording
	{
		if (IsRecording[client])
		{
			ClientCommand(client, "stop");
			PrintToChat(client, "[%s] Stopped recording.", g_tag);
			IsRecording[client] = false;
			Panel_Record_Main(client, 1);
		}

		else
		{
			IsRecording[client] = true;
			StartRecord(client);
			Panel_Record_Main(client, 2);
		}
	}

	else if (choice == 2) // Recording preferences
	{
		Handle panel = CreatePanel();
		SetPanelTitle(panel, "Recording preferences");

		DrawPanelText(panel, " ");

		char prefBuffer[128];

		if (g_preference[client] == PREF_WHOLE_MAPS)
			Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_prefWholeMaps);

		else if (g_preference[client] == PREF_HIGHLIGHTS)
			Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_prefHighlights);

		else
			Format(prefBuffer, sizeof(prefBuffer), "Recording mode: %s", g_prefAllRounds);

		DrawPanelText(panel, prefBuffer);

		DrawPanelText(panel, " ");

		DrawPanelItem(panel, "Change behaviour");

		DrawPanelItem(panel, "Back");

		SendPanelToClient(panel, client, PanelHandler_Preferences, 20);

		CloseHandle(panel);
	}

	else if (choice == 3) // Edit highlight mode criteria (XP)
	{
		Handle panel = CreatePanel();
		SetPanelTitle(panel, "Edit highlight mode criteria");

		DrawPanelText(panel, " ");

		char buffer[128];
		Format(buffer, sizeof(buffer), "Current threshold for keeping a round replay: %i XP", highlightXPThreshold[client]);
		DrawPanelText(panel, buffer);

		DrawPanelText(panel, " ");

		DrawPanelItem(panel, "Edit XP threshold for saving a round replay");
		DrawPanelItem(panel, "Back");

		SendPanelToClient(panel, client, PanelHandler_HighlightCriteria, 20);

		CloseHandle(panel);
	}

	else if (choice == 4) // Show help
	{
		Handle panel = CreatePanel();
		SetPanelTitle(panel, "Help");

		DrawPanelText(panel, " ");

		DrawPanelItem(panel, "What does this do?");
		DrawPanelItem(panel, "How does the highlights mode work?");
		DrawPanelItem(panel, "I have a feature request! I found a bug!");
		DrawPanelItem(panel, "Where can I get this plugin?");
		DrawPanelItem(panel, "Back");

		SendPanelToClient(panel, client, PanelHandler_Help, 20);

		CloseHandle(panel);
	}

	return Plugin_Handled;
}

void GenerateRandomID(int client)
{
	strcopy(g_randomID[client], sizeof(g_randomID), ""); // Empty the string first

	char charArray[62][1] = // Array of 0-9, a-Z
	{
		"0",
		"1",
		"2",
		"3",
		"4",
		"5",
		"6",
		"7",
		"8",
		"9",
		"a",
		"b",
		"c",
		"d",
		"e",
		"f",
		"g",
		"h",
		"i",
		"j",
		"k",
		"l",
		"m",
		"n",
		"o",
		"p",
		"q",
		"r",
		"s",
		"t",
		"u",
		"v",
		"w",
		"x",
		"y",
		"z",
		"A",
		"B",
		"C",
		"D",
		"E",
		"F",
		"G",
		"H",
		"I",
		"J",
		"K",
		"L",
		"M",
		"N",
		"O",
		"P",
		"Q",
		"R",
		"S",
		"T",
		"U",
		"V",
		"W",
		"X",
		"Y",
		"Z"
	};

	for (int i = 0; i < 10; i++)
	{
		// Concatenate a random character from the array one at a time
		StrCat(g_randomID[client], sizeof(g_randomID), charArray[GetRandomInt(0, 61)]);
	}
}
