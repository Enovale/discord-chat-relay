#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <discord>
#include <socket>
#include <ripext>
#include <morecolors>

#pragma newdecls required


// Socket Handles
Handle gH_Socket = INVALID_HANDLE;

// Clients
ArrayList gAL_Clients;

// Discord Bot
DiscordBot gDB_Bot = view_as<DiscordBot>(INVALID_HANDLE);

// ConVars
ConVar gCV_DiscordChatChannel;
ConVar gCV_DiscordWebhookLink;

ConVar gCV_DiscordEnable;
ConVar gCV_DiscordWebhookModeEnable;

ConVar gCV_SteamApiKey;

ConVar gCV_SocketEnable;
ConVar gCV_SocketPort;

ConVar gCV_ServerMessageTag;
ConVar gCV_DiscordMessageTag;
ConVar gCV_DiscordMessageFormat;
ConVar gCV_DiscordNameFormat;
ConVar gCV_DiscordNewTalkFormat;
ConVar gCV_DiscordMapChangeFormat;
ConVar gCV_DiscordPlayerConnectFormat;
ConVar gCV_DiscordPlayerDisconnectFormat;

ConVar gCV_CondensePlayerEvents;

// Cached values
char gS_BotToken[128];
char gS_WebhookLink[128];

char gS_ServerTag[128];
char gS_DiscordTag[128];
char gS_DiscordMessageFormat[1024];
char gS_DiscordNameFormat[512];
char gS_DiscordNewTalkFormat[512];
char gS_DiscordMapChangeFormat[512];
char gS_DiscordPlayerConnectFormat[512];
char gS_DiscordPlayerDisconnectFormat[512];
char szAPIKey[256];

HTTPClient httpClient;
char g_szSteamAvatar[MAXPLAYERS + 1][256];
char g_lastMessageAuthorId[64];
char g_connectQueue[(MAXPLAYERS * MAX_NAME_LENGTH) + (sizeof(", ") * MAXPLAYERS - 1)];
char g_disconnectQueue[sizeof(g_connectQueue)];

bool gB_ListeningToDiscord = false;

public Plugin myinfo =
{
	name = "Discord Chat Relay Deluxe",
	author = "Enova, Credits to PaxPlay, Ryan \"FLOOR_MASTER\" Mannion, shavit and Deathknife, +SyntX",
	description = "Chat relay for Discord with pretty printed and compact output.",
	version = "1.2.4",
	url = ""
};

public void OnPluginStart()
{
	gCV_DiscordChatChannel = CreateConVar("sm_discord_text_channel_id", "", "The Discord text channel id.");
	gCV_DiscordWebhookLink = CreateConVar("sm_discord_webhook_link", "", "The Discord webhook to use if sm_discord_webhook_mode_enable is enabled.");
	gCV_DiscordWebhookModeEnable = CreateConVar("sm_discord_webhook_mode_enable", "0", "Enable the pretty webhook mode for the discord relay.", 0, true, 0.0, true, 1.0);

	gCV_DiscordEnable = CreateConVar("sm_discord_relay_enable", "1", "Enable the chat relay with Discord.", 0, true, 0.0, true, 1.0);

	gCV_SteamApiKey = CreateConVar("sm_steam_api_key", "", "A steam API key is needed to get avatar URLs");

	gCV_SocketEnable = CreateConVar("sm_discord_socket_enable", "0", "Enable the cross server chat relay.", 0, true, 0.0, true, 1.0);
	gCV_SocketPort = CreateConVar("sm_discord_socket_port", "13370", "Port for the cross server chat relay socket.");

	gCV_ServerMessageTag = CreateConVar("sm_discord_chat_prefix_server", "{grey}[{green}SERVER{grey}]", "Chat Tag for messages from the server.");
	gCV_DiscordMessageTag = CreateConVar("sm_discord_chat_prefix_discord", "{grey}[{blue}DISCORD{grey}]", "Chat Tag for messages from discord.");
	gCV_DiscordMessageFormat = CreateConVar("sm_discord_chat_message_format", "{MESSAGE}", "How to format the message portion of the discord relay");
	gCV_DiscordNameFormat = CreateConVar("sm_discord_chat_name_format", "{NAME}", "How to format the name portion of the discord relay");
	gCV_DiscordNewTalkFormat = CreateConVar("sm_discord_new_talk_format", "-# {NAME} | {STEAM32}", "Format text for when a new person talks, for compact output");
	gCV_DiscordMapChangeFormat = CreateConVar("sm_discord_map_change_format", "-# Map Change: {NEWMAP}", "Format text for when a map change is happening.");
	gCV_DiscordPlayerConnectFormat = CreateConVar("sm_discord_player_connect_format", "-# {NAME} connected.", "Format text for when someone connects.");
	gCV_DiscordPlayerDisconnectFormat = CreateConVar("sm_discord_player_disconnect_format", "-# {NAME} disconnected.", "Format text for when someone disconnects.");

	gCV_CondensePlayerEvents = CreateConVar("sm_discord_condense_player_events", "1", "Should player connect/disconnect events be condensed in a delayed queue.", 0, true, 0.0, true, 1.0);

	gCV_ServerMessageTag.AddChangeHook(OnConVarChanged);
	gCV_DiscordMessageTag.AddChangeHook(OnConVarChanged);
	gCV_DiscordMessageFormat.AddChangeHook(OnConVarChanged);
	gCV_DiscordNameFormat.AddChangeHook(OnConVarChanged);
	gCV_DiscordNewTalkFormat.AddChangeHook(OnConVarChanged);
	gCV_DiscordMapChangeFormat.AddChangeHook(OnConVarChanged);
	gCV_DiscordPlayerConnectFormat.AddChangeHook(OnConVarChanged);
	gCV_DiscordPlayerDisconnectFormat.AddChangeHook(OnConVarChanged);

	AutoExecConfig(true, "discord-chat-relay-server", "sourcemod");
	if (gCV_CondensePlayerEvents.BoolValue)
	{
		CreateTimer(5.0, OnCheckForPlayerEvents, 0, TIMER_REPEAT);
	}
}

public Action OnCheckForPlayerEvents(Handle timer, any data)
{
	if (!StrEqual(gS_DiscordPlayerConnectFormat, "", true) && !StrEqual(g_connectQueue, "", true))
	{
		SendOutput(FormatContentWithReplacements(gS_DiscordPlayerConnectFormat, g_connectQueue, "", -1), "Server Events", -1, false);
		g_connectQueue = "";
	}

	if (!StrEqual(gS_DiscordPlayerDisconnectFormat, "", true) && !StrEqual(g_disconnectQueue, "", true))
	{
		SendOutput(FormatContentWithReplacements(gS_DiscordPlayerDisconnectFormat, g_disconnectQueue, "", -1), "Server Events", -1, false);
		g_disconnectQueue = "";
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	UpdateCvars();
}

void UpdateCvars()
{
	char buffer[128];
	gCV_ServerMessageTag.GetString(buffer, sizeof(buffer));
	FormatEx(gS_ServerTag, sizeof(gS_ServerTag), "%s", buffer);	// Update Gameserver Chat Tag

	gCV_DiscordMessageTag.GetString(buffer, sizeof(buffer));
	FormatEx(gS_DiscordTag, sizeof(gS_DiscordTag), "%s", buffer);	// Update Discord Chat Tag

	gCV_DiscordMessageFormat.GetString(gS_DiscordMessageFormat, sizeof(gS_DiscordMessageFormat));
	gCV_DiscordNameFormat.GetString(gS_DiscordNameFormat, sizeof(gS_DiscordNameFormat));
	gCV_DiscordNewTalkFormat.GetString(gS_DiscordNewTalkFormat, sizeof(gS_DiscordNewTalkFormat));
	gCV_DiscordMapChangeFormat.GetString(gS_DiscordMapChangeFormat, sizeof(gS_DiscordMapChangeFormat));
	gCV_DiscordPlayerConnectFormat.GetString(gS_DiscordPlayerConnectFormat, sizeof(gS_DiscordPlayerConnectFormat));
	gCV_DiscordPlayerDisconnectFormat.GetString(gS_DiscordPlayerDisconnectFormat, sizeof(gS_DiscordPlayerDisconnectFormat));

	GetConVarString(gCV_DiscordWebhookLink, gS_WebhookLink, sizeof(gS_WebhookLink));

	// Update and cache steam api key
	GetConVarString(gCV_SteamApiKey, szAPIKey, sizeof(szAPIKey));
    if (StrEqual(szAPIKey, "", false))
    {
        PrintToConsole(0, "[Infra-DCR] ERROR: Steam API Key not configured.");
        return;
    }
}

bool LoadConfig()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/dcr.cfg");

	if (!FileExists(sPath))
	{
		File hFile = OpenFile(sPath, "w");
		WriteFileLine(hFile, "\"discord-chat-relay\"");
		WriteFileLine(hFile, "{");
		WriteFileLine(hFile, "\t\"bot-token\"\t\"<insert-bot-token>\"");
		WriteFileLine(hFile, "}");
		CloseHandle(hFile);

		LogError("[Discord Chat Relay] \"%s\" not found, creating!", sPath);
		return false;
	}

	KeyValues kv = new KeyValues("discord-chat-relay");

	if(!kv.ImportFromFile(sPath))
	{
		delete kv;
		LogError("[Discord Chat Relay] Couldnt import KeyValues from \"%s\"!", sPath);

		return false;
	}

	kv.GetString("bot-token", gS_BotToken, sizeof(gS_BotToken));

	LogMessage("Loaded the BotToken.");

	delete kv;
	return true;
}

public void OnAllPluginsLoaded()
{
	if(gDB_Bot != view_as<DiscordBot>(INVALID_HANDLE))
		return;

	if (LoadConfig())
		gDB_Bot = new DiscordBot(gS_BotToken);
	else
		LogError("Couldnt load the Discord Chat Relay config.");
}

public void OnConfigsExecuted()
{
	UpdateCvars();

	if (gCV_DiscordEnable.BoolValue && gDB_Bot != view_as<DiscordBot>(INVALID_HANDLE))
	{
		if(!gB_ListeningToDiscord)
			gDB_Bot.GetGuilds(GuildList, INVALID_FUNCTION);
	}

	if (httpClient != null)
    	delete httpClient;

    httpClient = new HTTPClient("https://api.steampowered.com");

	if(gCV_SocketEnable.BoolValue && gH_Socket == INVALID_HANDLE)
	{
		char ip[24];
		int port = gCV_SocketPort.IntValue;
		GetServerIP(ip, sizeof(ip));

		gH_Socket = SocketCreate(SOCKET_TCP, OnSocketError);
		SocketBind(gH_Socket, ip, port);
		SocketListen(gH_Socket, OnSocketIncoming);

		gAL_Clients = CreateArray();

		LogMessage("[Discord Chat Relay] Started Server Chat Relay server on port %d", port);
	}

	if (!StrEqual(szAPIKey, "", false))
	{
		// Get steam avatars for existing players in case of plugin reload
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientConnected(i) && !IsFakeClient(i) && !IsClientSourceTV(i)) {
				GetProfilePic(i);
			}
		}
	}
}

public void GuildList(DiscordBot bot, char[] id, char[] name, char[] icon, bool owner, int permissions, any data)
{
	gDB_Bot.GetGuildChannels(id, ChannelList, INVALID_FUNCTION);
}

public void ChannelList(DiscordBot bot, char[] guild, DiscordChannel Channel, any data)
{
	if(Channel.IsText) {
		char id[32];
		Channel.GetID(id, sizeof(id));

		char sChannelID[64];
		gCV_DiscordChatChannel.GetString(sChannelID, sizeof(sChannelID));

		if(StrEqual(id, sChannelID) && !gB_ListeningToDiscord)
		{
			gDB_Bot.StopListening();

			char name[32];
			Channel.GetName(name, sizeof(name));
			gDB_Bot.MessageCheckInterval = 2.0;
			gDB_Bot.StartListeningToChannel(Channel, OnMessage);

			LogMessage("[Discord Chat Relay] Started listening to channel %s (%s)", name, id);
			gB_ListeningToDiscord = true;
		}
	}
}

public void OnMessage(DiscordBot Bot, DiscordChannel Channel, DiscordMessage message)
{
	if (message.GetAuthor().IsBot())
		return;

	char sMessage[2048];
	message.GetContent(sMessage, sizeof(sMessage));

	char sAuthor[128];
	DiscordUser author = message.GetAuthor();
	author.GetUsername(sAuthor, sizeof(sAuthor));

	char sAuthorId[64];
	author.GetID(sAuthorId, sizeof(sAuthorId));
    Format(g_lastMessageAuthorId, sizeof(g_lastMessageAuthorId), "%s", sAuthorId);
	Format(sMessage, sizeof(sMessage), "%s %s: %s", gS_DiscordTag, sAuthor, sMessage);

	CPrintToChatAll("%s", sMessage);
	Broadcast(INVALID_HANDLE, sMessage, sizeof(sMessage));
}

public void CP_OnChatMessagePost(int author, ArrayList recipients, const char[] flagstring, const char[] formatstring, const char[] name, const char[] message, bool processcolors, bool removecolors)
{
	if(message[0] == '!' || message[1] == '!') // remove chat commands
		return;

	char sMessage[512];
	Format(sMessage, sizeof(sMessage), "%s %s: %s", gS_ServerTag, name, message);

	Broadcast(INVALID_HANDLE, sMessage, sizeof(sMessage));

	char szSteamID[64];

    GetClientAuthId(author, AuthId_SteamID64, szSteamID, sizeof(szSteamID), true);

	if (!gCV_DiscordWebhookModeEnable.BoolValue)
	{
		SendToDiscord(sMessage ,sizeof(sMessage));
	}
	else
	{
		Format(sMessage, sizeof(sMessage), "%s", message);
		char nMessage[512];
		Format(nMessage, sizeof(nMessage), "%s", name);

		if (!StrEqual(szSteamID, g_lastMessageAuthorId))
		{
			SanitiseText(nMessage, sizeof(nMessage));
			SanitiseText(sMessage, sizeof(sMessage));
			char cMessage[1024];
			Format(cMessage, sizeof(cMessage), "%s\n%s", FormatContentWithReplacements(gS_DiscordNewTalkFormat, nMessage, "", author), FormatContentWithReplacements(gS_DiscordMessageFormat, nMessage, sMessage, author));
			SendOutput(cMessage, nMessage, author, false);
		}
		else
		{
			SendToWebhook(sMessage ,sizeof(sMessage), nMessage, sizeof(nMessage), author);
		}
	}

    Format(g_lastMessageAuthorId, sizeof(g_lastMessageAuthorId), "%s", szSteamID);
}

public void OnClientPostAdminCheck(int client)
{
    GetProfilePic(client);
}

public void OnClientAuthorized(int client)
{
	char sMessage[MAX_NAME_LENGTH];
	GetClientName(client, sMessage, sizeof(sMessage));
	SanitiseText(sMessage, sizeof(sMessage));
	if (!StrEqual(gS_DiscordPlayerConnectFormat, "", true) && !gCV_CondensePlayerEvents.BoolValue)
	{
		SendOutput(FormatContentWithReplacements(gS_DiscordPlayerConnectFormat, sMessage, "", client), "Server Events", client, false);
	}
	else
	{
		if (StrEqual(g_connectQueue, "", true))
		{
			Format(g_connectQueue, sizeof(g_connectQueue), "%s", sMessage);
		}
		else
		{
			Format(g_connectQueue, sizeof(g_connectQueue), "%s, %s", g_connectQueue, sMessage);
		}
	}
}

public void OnMapInit(const char[] mapName)
{
	if (!StrEqual(gS_DiscordMapChangeFormat, "", true))
	{
		char sMessage[512];
		Format(sMessage, sizeof(sMessage), "%s", mapName);
		SanitiseText(sMessage, sizeof(sMessage));
		SendOutput(FormatContentWithReplacements(gS_DiscordMapChangeFormat, sMessage, "", -1), "Server Events", -1, false);
	}
}

public void OnClientDisconnect(int client)
{
	char sMessage[MAX_NAME_LENGTH];
	GetClientName(client, sMessage, sizeof(sMessage));
	SanitiseText(sMessage, sizeof(sMessage));
	if (!StrEqual(gS_DiscordPlayerDisconnectFormat, "", true) && !gCV_CondensePlayerEvents.BoolValue)
	{
		SendOutput(FormatContentWithReplacements(gS_DiscordPlayerDisconnectFormat, sMessage, "", client), "Server Events", client, false);
	}
	else
	{
		if (StrEqual(g_disconnectQueue, "", true))
		{
			Format(g_disconnectQueue, sizeof(g_disconnectQueue), "%s", sMessage);
		}
		else
		{
			Format(g_disconnectQueue, sizeof(g_disconnectQueue), "%s, %s", g_disconnectQueue, sMessage);
		}
	}
}

public void OnMessageSent(DiscordBot bot, char[] channel, DiscordMessage message, any data)
{
	char sMessage[2048];
	message.GetContent(sMessage, sizeof(sMessage));
	LogMessage("[SM] Message sent to discord: \"%s\".", sMessage);
}

void GetServerIP(char[] ip, int length)
{
	int hostip = FindConVar("hostip").IntValue;

	Format(ip, length, "%d.%d.%d.%d",
		(hostip >> 24 & 0xFF),
		(hostip >> 16 & 0xFF),
		(hostip >> 8 & 0xFF),
		(hostip & 0xFF)
		);
}

bool Broadcast(Handle socket, const char[] message, int maxlength)
{
	if(!gCV_SocketEnable.BoolValue)
		return false;

	if(gAL_Clients == INVALID_HANDLE)
	{
		LogError("In Broadcast, gAL_Clients was invalid. This should never happen!");
		return false;
	}


	int size = gAL_Clients.Length;
	Handle dest_socket = INVALID_HANDLE;

	for (int i = 0; i < size; i++)
	{
		dest_socket = gAL_Clients.Get(i);
		if (dest_socket != socket) // Prevent sending back to the same server.
		{
			SocketSend(dest_socket, message, maxlength);
		}
	}

	if (socket != INVALID_HANDLE) // Prevent printing to the server chat, if message is by the server.
	{
		CPrintToChatAll("%s", message);
	}
	return true;
}

void CloseSocket()
{
	if(gH_Socket != INVALID_HANDLE)
	{
		CloseHandle(gH_Socket);
		gH_Socket = INVALID_HANDLE;
		LogMessage("Closed local Server Chat Relay socket");
	}
	if(gAL_Clients != INVALID_HANDLE)
	{
		CloseHandle(gAL_Clients);
	}
}

void RemoveClient(Handle client)
{

	if (gAL_Clients == INVALID_HANDLE)
	{
		LogError("Attempted to remove client while g_clients was invalid. This should never happen!");
		return;
	}

	int size = gAL_Clients.Length;
	for (int i = 0; i < size; i++)
	{
		if(gAL_Clients.Get(i) == client)
		{
			gAL_Clients.Erase(i);
			return;
		}
	}

	LogError("Could not find client in RemoveClient. This should never happen!");
}

public int OnSocketIncoming(Handle socket, Handle newSocket, char[] remoteIP, int remotePort, any arg)
{
	if (gAL_Clients == INVALID_HANDLE) {
		LogError("In OnSocketIncoming, gAL_Clients was invalid. This should never happen!");
	}
	else {
		PushArrayCell(gAL_Clients, newSocket);
	}

	SocketSetReceiveCallback(newSocket, OnChildSocketReceive);
	SocketSetDisconnectCallback(newSocket, OnChildSocketDisconnected);
	SocketSetErrorCallback(newSocket, OnChildSocketError);
}

public int OnSocketDisconnected(Handle socket, any arg)
{
	CloseSocket();
}

public int OnSocketError(Handle socket, const int errorType, const int errorNum, any arg)
{
	LogError("Socket error %d (errno %d)", errorType, errorNum);
	CloseSocket();
}

public int OnChildSocketReceive(Handle socket, char[] receiveData, const int dataSize, any arg)
{
	Broadcast(socket, receiveData, dataSize);

	SendToDiscord(receiveData, dataSize);
}

public int OnChildSocketDisconnected(Handle socket, any arg) {
	RemoveClient(socket);
	CloseHandle(socket);
}

public int OnChildSocketError(Handle socket, const int errorType, const int errorNum, any arg)
{
	LogError("Child socket error %d (errno %d)", errorType, errorNum);
	RemoveClient(socket);
	CloseHandle(socket);
}

void SendOutput(const char[] message, const char[] name, int client, bool discord)
{
	if (discord)
	{
		char[] sMessage = new char[1024];
		FormatEx(sMessage, 1024, "%s", message);

		char sChannelID[64];
		gCV_DiscordChatChannel.GetString(sChannelID, sizeof(sChannelID));
		gDB_Bot.SendMessageToChannelID(sChannelID, sMessage, OnMessageSent);
	}
	else
	{
		DiscordWebHook hook = new DiscordWebHook(gS_WebhookLink);
		hook.SlackMode = true;

		hook.SetContent(message);

		hook.SetUsername(name);

		if (client >= 0 && !StrEqual(g_szSteamAvatar[client], "NULL", false) && !StrEqual(g_szSteamAvatar[client], "", false))
		{
			PrintToConsole(0, "[Infra-DCR] DEBUG: Client %s has an avatar, using it! URL: %s", 	client, g_szSteamAvatar[client]);
			hook.SetAvatar(g_szSteamAvatar[client]);
		}
		hook.Send();
		delete hook;
	}
}

void SendToDiscord(const char[] message, int maxlength)
{
	char[] sMessage = new char[maxlength];
	FormatEx(sMessage, maxlength, "%s", message);

    SanitiseText(sMessage, maxlength);

	char[] fMessage = new char[1024];
	FormatEx(fMessage, 1024, "%s", FormatContentWithReplacements(gS_DiscordMessageFormat, "", sMessage, -1));

	char sChannelID[64];
	gCV_DiscordChatChannel.GetString(sChannelID, sizeof(sChannelID));
	gDB_Bot.SendMessageToChannelID(sChannelID, fMessage, OnMessageSent);
}

void SendToWebhook(char[] message, int messageLength, char[] authorName, int nameLength, int client)
{
	char webhook[1024];
	GetConVarString(gCV_DiscordWebhookLink, webhook, sizeof(webhook));
	DiscordWebHook hook = new DiscordWebHook(webhook);
    hook.SlackMode = true;

    SanitiseText(message, messageLength);
    SanitiseText(authorName, nameLength);
    hook.SetContent(FormatContentWithReplacements(gS_DiscordMessageFormat, authorName, message, client));

    hook.SetUsername(FormatContentWithReplacements(gS_DiscordNameFormat, authorName, message, client));

    if (client >= 0 && !StrEqual(g_szSteamAvatar[client], "NULL", false) && !StrEqual(g_szSteamAvatar[client], "", false))
    {
        PrintToConsole(0, "[Infra-DCR] DEBUG: Client %s has an avatar, using it! URL: %s", client, g_szSteamAvatar[client]);
        hook.SetAvatar(g_szSteamAvatar[client]);
    }
    hook.Send();
    delete hook;
}

void SanitiseText(char[] text, int maxLength)
{
    ReplaceString(text, maxLength, "@", "", false);
    ReplaceString(text, maxLength, "`", "", false);
    ReplaceString(text, maxLength, "\\", "", false);
    ReplaceString(text, maxLength, "||", "", false);
    //ReplaceString(text, maxLength, "# ", "", false);
    //ReplaceString(text, maxLength, "## ", "", false);
    //ReplaceString(text, maxLength, "### ", "", false);

	CRemoveTags(text, maxLength);
}

char[] FormatContentWithReplacements(char[] original, const char[] authorName, const char[] message, int client)
{
	char buffer[256], sMessage[768];
	strcopy(sMessage, sizeof(sMessage), original);

	if (client >= 0 && StrContains(sMessage, "{STEAM32}", false) != -1) {
		GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
		ReplaceString(sMessage, sizeof(sMessage), "{STEAM32}", buffer);
	}
	if (StrContains(sMessage, "{MESSAGE}", false) != -1) {
		ReplaceString(sMessage, sizeof(sMessage), "{MESSAGE}", message);
	}
	if (StrContains(sMessage, "{NAME}", false) != -1) {
		ReplaceString(sMessage, sizeof(sMessage), "{NAME}", authorName);
	}
	// We just send the new map whenever this would be used.
	// This sucks. I know.
	if (StrContains(sMessage, "{NEWMAP}", false) != -1) {
		ReplaceString(sMessage, sizeof(sMessage), "{NEWMAP}", authorName);
	}

	ReplaceString(sMessage, sizeof(sMessage), "\\n", "\n");
	return sMessage;
}

void GetProfilePic(int client)
{
    char szRequestBuffer[1024], szSteamID[64];

    GetClientAuthId(client, AuthId_SteamID64, szSteamID, sizeof(szSteamID), true);
    if (StrEqual(szAPIKey, "", false))
    {
        PrintToConsole(0, "[Infra-DCR] ERROR: Steam API Key not configured.");
        return;
    }

    Format(szRequestBuffer, sizeof szRequestBuffer, "ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s&format=json", szAPIKey, szSteamID);
    httpClient.Get(szRequestBuffer, GetProfilePicCallback, client);
}

public void GetProfilePicCallback(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK)
    {
        FormatEx(g_szSteamAvatar[client], sizeof(g_szSteamAvatar[]), "NULL");
        PrintToConsole(0, "[Infra-DCR] ERROR: Failed to reach SteamAPI. Status: %i", response.Status);
        return;
    }

    JSONObject objects = view_as<JSONObject>(response.Data);
    JSONObject Response = view_as<JSONObject>(objects.Get("response"));
    JSONArray players = view_as<JSONArray>(Response.Get("players"));
    int playerlen = players.Length;
    PrintToConsole(0, "[Infra-DCR] DEBUG: Client %i SteamAPI Response Length: %i", client, playerlen);

    JSONObject player;
    for (int i = 0; i < playerlen; i++)
    {
        player = view_as<JSONObject>(players.Get(i));
        player.GetString("avatarfull", g_szSteamAvatar[client], sizeof(g_szSteamAvatar[]));
        PrintToConsole(0, "[Infra-DCR] DEBUG: Client %i has Avatar URL: %s", client, g_szSteamAvatar[client]);
        delete player;
    }
}
