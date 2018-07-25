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
#include <ripext>
#include <smlib>
#include <sourcemod>

public Plugin myinfo =
{
    name = "NeonSM",
    description = "Neon SourceMod",
    author = "danthonywalker#5512",
    version = "0.1.1",
    url = "https://github.com/neon-bot-project/NeonSM"
}

static ConVar neonSmChannelId;
static ConVar neonSmCredentials;
static HTTPClient httpClient;

#define BUFFER_SIZE 255
static char BUFFER[BUFFER_SIZE];

public void OnPluginStart()
{
    // ConVar values are not loaded until OnConfigsExecuted() is executed (so wait to initialize the HTTPClient)
    neonSmChannelId = CreateConVar("neonsm_channel_id", "", "The ID of the channel for NeonSM to communicate.");
    neonSmCredentials = CreateConVar("neonsm_credentials", "", "Secret credentials for neonsm_channel_id.");
    AutoExecConfig(true, "neonsm");

    // Post a checkpoint and retrieve events every second
    CreateTimer(1.0, PostCheckpoint, _, TIMER_REPEAT);

    HookEvent("player_say", Event_PlayerSay);
}

public void OnPluginEnd()
{
    // TODO: Add metadata to apply here and on ON_PLGUIN_START
    PostEvent("GENERIC", "ON_PLGUIN_END", new JSONObject());
}

public void OnConfigsExecuted()
{
    if (httpClient == null)
    {
        char buffer[BUFFER_SIZE] = "https://neon.yockto.technology/api/v1/channels/";
        GetConVarString(neonSmChannelId, BUFFER, BUFFER_SIZE);
        StrCat(buffer, BUFFER_SIZE, BUFFER);
        httpClient = new HTTPClient(buffer);

        buffer = "Basic "; // Basic Authorization header prefix
        GetConVarString(neonSmCredentials, BUFFER, BUFFER_SIZE);
        StrCat(buffer, BUFFER_SIZE, BUFFER);
        httpClient.SetHeader("Authorization", buffer);

        // Additional headers required by Neon REST server
        httpClient.SetHeader("Accept", "application/json");
        httpClient.SetHeader("Content-Type", "application/json");

        // Fulfills same functionality as OnPluginStart() would
        PostEvent("GENERIC", "ON_PLGUIN_START", new JSONObject());
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
        PostEvent("GENERIC", "ON_LOG_ACTION", payload);
    }

    return Plugin_Continue;
}

public void OnMapStart()
{
    JSONObject payload = new JSONObject();

    GetCurrentMap(BUFFER, BUFFER_SIZE);
    payload.SetString("name", BUFFER);

    PostEvent("GENERIC", "ON_MAP_START", payload);
}

public void OnMapEnd()
{
    JSONObject payload = new JSONObject();

    GetCurrentMap(BUFFER, BUFFER_SIZE);
    payload.SetString("name", BUFFER);

    PostEvent("GENERIC", "ON_MAP_END", payload);
}

public void OnClientConnected(int client)
{
    PostEvent("GENERIC", "CLIENT_CONNECTED", GetJSONClientInfo(client));
}

public void OnClientDisconnect(int client)
{
    PostEvent("GENERIC", "CLIENT_DISCONNECT", GetJSONClientInfo(client));
}

static void Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
    JSONObject payload = new JSONObject();
    event.GetString("text", BUFFER, BUFFER_SIZE);
    payload.SetString("text", BUFFER);

    int client = GetClientOfUserId(event.GetInt("userid"));
    payload.Set("client", GetJSONClientInfo(client));
    PostEvent("GENERIC", "PLAYER_SAY", payload);
}

static Action PostCheckpoint(Handle timer)
{
    if (httpClient != null)
    { // TODO: Replace this endpoint for a decent SourceMod WebSocket implementation
        httpClient.Post("/checkpoints", new JSONObject(), PostCheckpointCallback);
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

            if (StrEqual(BUFFER, "ALL_MESSAGE"))
            {
                payload.GetString("payload", BUFFER, BUFFER_SIZE);
                Color_ParseChatText(BUFFER, BUFFER, BUFFER_SIZE);
                Client_PrintToChatAll(false, BUFFER);
            }
        }
    }
}

static void PostEvent(const char[] type, const char[] subType, JSONObject subPayload)
{
    if (httpClient != null)
    {
        JSONObject payload = new JSONObject();
        payload.SetString("type", subType);
        payload.Set("payload", subPayload);
        JSONObject request = new JSONObject();
        request.SetString("type", type);
        request.Set("payload", payload);
        httpClient.Post("/events", request, PostCallback);
    }
}

static void PostCallback(HTTPResponse response, any value)
{
    // Disables HTTPClient until OnConfigsExecuted()
    if (response.Status != HTTPStatus_OK)
    {
        response.Data.ToString(BUFFER, BUFFER_SIZE);
        httpClient = null; // Call before LogError because of OnLogAction()
        LogError("Failed HTTP Request (%d): %s", response.Status, BUFFER);
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

    // Below can throw errors because of "no mod support"
    clientInfo.SetInt("frags", GetClientFrags(client));
    clientInfo.SetInt("deaths", GetClientDeaths(client));
    clientInfo.SetInt("health", GetClientHealth(client));
    clientInfo.SetInt("armor", GetClientArmor(client));
    GetClientWeapon(client, BUFFER, BUFFER_SIZE);
    clientInfo.SetString("weapon", BUFFER);

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
