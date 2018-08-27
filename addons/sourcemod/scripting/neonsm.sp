/*
 * This file is part of NeonSM.
 *
 * NeonSM is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * NeonSM is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NeonSM.  If not, see <https://www.gnu.org/licenses/>.
 */
#include <morecolors>
#include <ripext>
#include <sourcemod>

public Plugin myinfo =
{
    name = "NeonSM",
    description = "Neon SourceMod",
    author = "danthonywalker#5512",
    version = "0.1.2",
    url = "https://github.com/neon-bot-project/NeonSM"
}

static ConVar neonSmChannelId;
static ConVar neonSmToken;
static HTTPClient httpClient;

#define BUFFER_SIZE 255
static char BUFFER[BUFFER_SIZE];

public void OnPluginStart()
{
    // ConVar values are not loaded until OnConfigsExecuted() is executed (so wait to initialize the HTTPClient)
    neonSmChannelId = CreateConVar("neonsm_channel_id", "", "The ID of the channel for NeonSM to communicate.");
    neonSmToken = CreateConVar("neonsm_token", "", "Secret token for neonsm_channel_id.");
    AutoExecConfig(true, "neonsm");

    // Post a checkpoint and retrieve events every second
    CreateTimer(1.0, PostCheckpoint, _, TIMER_REPEAT);

    HookEvent("player_say", Event_PlayerSay);
    HookEvent("player_connect", Event_PlayerConnect);
    HookEvent("player_disconnect", Event_PlayerDisconnect);
}

public void OnPluginEnd()
{
    // TODO: Apply metadata and on ON_PLUGIN_START
    PostEvent("ON_PLUGIN_END", new JSONObject());
}

public void OnConfigsExecuted()
{
    if (httpClient == null)
    {
        char buffer[BUFFER_SIZE] = "https://neon.yockto.technology/api/v1/channels/";
        GetConVarString(neonSmChannelId, BUFFER, BUFFER_SIZE);
        StrCat(buffer, BUFFER_SIZE, BUFFER);
        httpClient = new HTTPClient(buffer);

        buffer = "Basic "; // Authorization header prefix
        GetConVarString(neonSmToken, BUFFER, BUFFER_SIZE);
        StrCat(buffer, BUFFER_SIZE, BUFFER);
        httpClient.SetHeader("Authorization", buffer);

        // Additional headers required by Neon REST server
        httpClient.SetHeader("Accept", "application/json");
        httpClient.SetHeader("Content-Type", "application/json");

        // Fulfills same functionality as OnPluginStart()
        PostEvent("ON_PLUGIN_START", new JSONObject());
    }
}

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
    if ((target == 0) || (target == -1))
    { // Only log actions targeting the console
        JSONObject payload = new JSONObject();

        switch (ident)
        {
            case Identity_Core:
            { // TODO: Get information about the client
                payload.SetString("source", "core");
            }
            case Identity_Extension:
            { // TODO: Get information about the extension
                payload.SetString("source", "extension");
            }
            case Identity_Plugin:
            {
                payload.SetString("source", "plugin");
                payload.Set("plugin", GetJSONPluginInfo(source));
            }
        }

        payload.SetString("message", message);
        PostEvent("ON_LOG_ACTION", payload);
    }

    return Plugin_Continue;
}

public void OnMapStart()
{
    JSONObject payload = new JSONObject();

    GetCurrentMap(BUFFER, BUFFER_SIZE);
    payload.SetString("name", BUFFER);

    PostEvent("ON_MAP_START", payload);
}

public void OnMapEnd()
{
    JSONObject payload = new JSONObject();

    GetCurrentMap(BUFFER, BUFFER_SIZE);
    payload.SetString("name", BUFFER);

    PostEvent("ON_MAP_END", payload);
}

static void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
    JSONObject payload = new JSONObject();
    event.GetString("text", BUFFER, BUFFER_SIZE);
    payload.SetString("text", BUFFER);

    int client = GetClientOfUserId(event.GetInt("userid"));
    payload.Set("client", GetJSONClientInfo(client));
    PostEvent("PLAYER_SAY", payload);
}

public void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
    JSONObject payload = new JSONObject();
    event.GetString("name", BUFFER, BUFFER_SIZE);
    payload.SetString("name", BUFFER);
    payload.SetInt("index", event.GetInt("index"));
    payload.SetInt("userid", event.GetInt("userid"));
    event.GetString("networkid", BUFFER, BUFFER_SIZE);
    payload.SetString("networkid", BUFFER);
    event.GetString("address", BUFFER, BUFFER_SIZE);
    payload.SetString("address", BUFFER);
    payload.SetInt("bot", event.GetInt("bot"));
    PostEvent("PLAYER_CONNECT", payload);
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    JSONObject payload = new JSONObject();
    payload.SetInt("userid", event.GetInt("userid"));
    event.GetString("reason", BUFFER, BUFFER_SIZE);
    payload.SetString("reason", BUFFER);
    event.GetString("name", BUFFER, BUFFER_SIZE);
    payload.SetString("name", BUFFER);
    event.GetString("networkid", BUFFER, BUFFER_SIZE);
    payload.SetString("networkid", BUFFER);
    event.SetInt("bot", event.GetInt("bot"))
    PostEvent("PLAYER_DISCONNECT", payload);
}

static Action PostCheckpoint(Handle timer)
{
    if (httpClient != null)
    { // TODO: Replace this endpoint for a decent SourceMod WebSocket implementation
        httpClient.Post("checkpoints", new JSONObject(), PostCheckpointCallback);
    }

    return Plugin_Continue;
}

static void PostCheckpointCallback(HTTPResponse response, any value)
{
    PostCallback(response, value);
    if (response.Status == HTTPStatus_OK)
    {
        JSONArray payloads = view_as<JSONArray>(response.Data);
        for (int index = 0; index < payloads.Length; index++)
        {
            JSONObject payload = view_as<JSONObject>(payloads.Get(index));
            payload.GetString("type", BUFFER, BUFFER_SIZE);

            if (StrEqual(BUFFER, "ALL_MESSAGES"))
            {
                payload.GetString("payload", BUFFER, BUFFER_SIZE);
                CPrintToChatAll(BUFFER); // #include <morecolors>
            }
        }
    }
}

static void PostEvent(const char[] type, JSONObject payload)
{
    if (httpClient != null)
    {
        JSONObject request = new JSONObject();
        request.SetString("type", type);
        request.Set("payload", payload);
        httpClient.Post("events", request, PostCallback);
    }
}

static void PostCallback(HTTPResponse response, any value)
{
    // Disables HTTPClient until OnConfigsExecuted(), ignoring errors if Neon is shutdown
    if ((response.Status != HTTPStatus_OK) && (response.Status != HTTPStatus_BadGateway))
    {
        CloseHandle(httpClient);
        httpClient = null; // Call before LogError because OnLogAction()
        LogError("Failed HTTP Request - Status: (%d)", response.Status);
    }
}

static JSONObject GetJSONClientInfo(int client)
{
    JSONObject clientInfo = new JSONObject();

    clientInfo.SetInt("client", client);
    clientInfo.SetInt("userId", GetClientUserId(client));
    GetClientAuthId(client, AuthId_SteamID64, BUFFER, BUFFER_SIZE);
    clientInfo.SetString("authId", BUFFER);
    GetClientName(client, BUFFER, BUFFER_SIZE);
    clientInfo.SetString("name", BUFFER);
    GetClientIP(client, BUFFER, BUFFER_SIZE);
    clientInfo.SetString("ip", BUFFER);
    clientInfo.SetFloat("latency", GetClientLatency(client, NetFlow_Both));
    clientInfo.SetFloat("avgPackets", GetClientAvgPackets(client, NetFlow_Both));
    clientInfo.SetFloat("avgLoss", GetClientAvgLoss(client, NetFlow_Both));
    clientInfo.SetFloat("avgData", GetClientAvgData(client, NetFlow_Both));

    return clientInfo;
}

static JSONObject GetJSONPluginInfo(Handle handle)
{
    JSONObject pluginInfo = new JSONObject();

    GetPluginInfo(handle, PlInfo_Name, BUFFER, BUFFER_SIZE);
    pluginInfo.SetString("name", BUFFER);
    GetPluginInfo(handle, PlInfo_Author, BUFFER, BUFFER_SIZE);
    pluginInfo.SetString("author", BUFFER);
    GetPluginInfo(handle, PlInfo_Description, BUFFER, BUFFER_SIZE);
    pluginInfo.SetString("description", BUFFER);
    GetPluginInfo(handle, PlInfo_Version, BUFFER, BUFFER_SIZE);
    pluginInfo.SetString("version", BUFFER);
    GetPluginInfo(handle, PlInfo_URL, BUFFER, BUFFER_SIZE);
    pluginInfo.SetString("url", BUFFER);

    return pluginInfo;
}
