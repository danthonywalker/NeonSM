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
#include <sourcemod>

public Plugin myinfo =
{
    name = "NeonSM",
    author = "danthonywalker#5512",
    description = "Neon SourceMod",
    version = "1.0.1",
    url = "https://github.com/NeonTech/NeonSM"
};

static HTTPClient httpClient;
static ConVar channelId;
static ConVar token;

static Handle onCheckpointGlobal;
static Handle onCheckpointPrivate;
static StringMap onCheckpoints;

static ArrayList eventRequests;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("HookCheckpoint", Native_HookCheckpoint);
    CreateNative("UnhookCheckpoint", Native_UnhookCheckpoint);
    CreateNative("HookCheckpointEx", Native_HookCheckpointEx);
    CreateNative("UnhookCheckpointEx", Native_UnhookCheckpointEx);
    CreateNative("PostEvent", Native_PostEvent);

    RegPluginLibrary("neonsm");
    return APLRes_Success;
}

public void OnPluginStart()
{
    // ConVar values are not loaded until OnConfigsExecuted() is called (so wait to initialize HTTPClient)
    channelId = CreateConVar("neonsm_channel_id", "", "The ID of the channel for NeonSM to communicate.");
    token = CreateConVar("neonsm_token", "", "The secret token for neonsm_channel_id.");
    AutoExecConfig(true, "neonsm", "neonsm");

    onCheckpoints = new StringMap();
    eventRequests = new ArrayList(1, 0);

    onCheckpointGlobal = CreateGlobalForward("OnCheckpoint", ET_Event, Param_String, Param_Cell);
    onCheckpointPrivate = CreateForward(ET_Event, Param_String, Param_Cell);
    CreateTimer(1.0, PostCheckpoint, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
    if (httpClient == INVALID_HANDLE)
    {
        char buffer[PLATFORM_MAX_PATH] = "https://api.neon.tech/channels/";
        char conVarBuffer[PLATFORM_MAX_PATH];

        GetConVarString(channelId, conVarBuffer, sizeof(conVarBuffer));
        StrCat(buffer, sizeof(buffer), conVarBuffer);
        httpClient = new HTTPClient(buffer);

        strcopy(buffer, sizeof(buffer), "Basic ");
        GetConVarString(token, conVarBuffer, sizeof(conVarBuffer));
        StrCat(buffer, sizeof(buffer), conVarBuffer);
        httpClient.SetHeader("Authorization", buffer);

        for (int index = 0; index < eventRequests.Length; index++)
        {
            DataPack pair = eventRequests.Get(index);
            Handle plugin = pair.ReadCell();
            JSONObject eventRequest = pair.ReadCell();
            pair.Close();

            PostEventEx(plugin, eventRequest);
        }

        eventRequests.Close();
    }
}

public int Native_PostEvent(Handle plugin, int numParams)
{
    int typeLength;
    GetNativeStringLength(1, typeLength);
    char[] type = new char[typeLength + 1];
    GetNativeString(1, type, typeLength + 1);
    JSONObject payload = GetNativeCell(2);

    JSONObject eventRequest = new JSONObject();
    eventRequest.SetString("type", type);
    eventRequest.Set("payload", payload);

    if (httpClient == INVALID_HANDLE)
    { // If PostEvent() is invoked before OnConfigsExecuted()
        eventRequests.Push(CreatePair(plugin, eventRequest));
    }
    else
    {
        PostEventEx(plugin, eventRequest);
    }
}

static void PostEventEx(Handle plugin, JSONObject eventRequest)
{
    httpClient.Post("events", eventRequest, HttpRequestCallback, CreatePair(plugin, eventRequest));
}

public Action PostCheckpoint(Handle timer)
{
    if (httpClient != INVALID_HANDLE)
    { // TODO Make a WebSocket implementation
        JSONObject request = new JSONObject();
        httpClient.Post("checkpoints", request, PostCheckpointCallback, CreatePair(GetMyHandle(), request));
    }

    return Plugin_Continue;
}

public int Native_HookCheckpoint(Handle plugin, int numParams)
{
    int typeLength;
    GetNativeStringLength(1, typeLength);
    char[] type = new char[typeLength + 1];
    GetNativeString(1, type, typeLength + 1);

    Handle fwd;
    if (!onCheckpoints.GetValue(type, fwd))
    {
        fwd = CreateForward(ET_Event, Param_String, Param_Cell);
        onCheckpoints.SetValue(type, fwd);
    }

    AddToForward(fwd, plugin, GetNativeFunction(2));
}

public int Native_UnhookCheckpoint(Handle plugin, int numParams)
{
    int typeLength;
    GetNativeStringLength(1, typeLength);
    char[] type = new char[typeLength + 1];
    GetNativeString(1, type, typeLength + 1);

    Handle fwd;
    if (onCheckpoints.GetValue(type, fwd))
    { // TODO Possibly track forward count for closing Handle
        RemoveFromForward(fwd, plugin, GetNativeFunction(2));
    }
}

public int Native_HookCheckpointEx(Handle plugin, int numParams)
{
    AddToForward(onCheckpointPrivate, plugin, GetNativeFunction(1));
}

public int Native_UnhookCheckpointEx(Handle plugin, int numParams)
{
    RemoveFromForward(onCheckpointPrivate, plugin, GetNativeFunction(1));
}

static void ForwardOnCheckpoint(Handle fwd, const char[] type, JSONObject payload)
{
    Call_StartForward(fwd);
    Call_PushString(type);
    Call_PushCell(payload);
    Call_Finish();
}

public void PostCheckpointCallback(HTTPResponse response, any value, const char[] error)
{
    HttpRequestCallback(response, value, error);
    if (response.Status == HTTPStatus_OK)
    {
        JSONArray checkpointResponses = view_as<JSONArray>(response.Data);
        for (int index = 0; index < checkpointResponses.Length; index++)
        {
            JSONObject checkpointResponse = view_as<JSONObject>(checkpointResponses.Get(index));

            static char type[PLATFORM_MAX_PATH];
            checkpointResponse.GetString("type", type, sizeof(type));
            JSONObject payload = view_as<JSONObject>(checkpointResponse.Get("payload"));

            Handle fwd;
            if (onCheckpoints.GetValue(type, fwd))
            {
                ForwardOnCheckpoint(fwd, type, payload);
            }

            ForwardOnCheckpoint(onCheckpointGlobal, type, payload);
            ForwardOnCheckpoint(onCheckpointPrivate, type, payload);
        }
    }
}

public void HttpRequestCallback(HTTPResponse response, any value, const char[] error)
{
    DataPack pair = value;
    Handle plugin = pair.ReadCell();
    JSONObject request = pair.ReadCell();
    pair.Close();

    HTTPStatus status = response.Status;
    if ((status != HTTPStatus_OK) && (plugin != INVALID_HANDLE))
    {
        // Do not waste permanent heap space (static) for errors
        char fileName[PLATFORM_MAX_PATH];
        char json[PLATFORM_MAX_PATH];

        GetPluginFilename(plugin, fileName, sizeof(fileName));
        LogError("%s Failed HTTP %d Error - %s", fileName, status, error);
        request.ToString(json, sizeof(json), JSON_COMPACT);
        LogError("%s Failed HTTP %d Request - %s", fileName, status, json);

        JSON responseBody = response.Data;
        if (responseBody != INVALID_HANDLE)
        {
            responseBody.ToString(json, sizeof(json), JSON_COMPACT);
            LogError("%s Failed HTTP %d Response - %s", fileName, status, json);
        }
    }

    request.Close();
}

static DataPack CreatePair(any first, any second)
{ // TODO Define an object for storing two values
    DataPack pair = new DataPack();
    pair.WriteCell(first);
    pair.WriteCell(second);
    pair.Reset();
    return pair;
}
