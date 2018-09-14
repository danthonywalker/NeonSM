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
#if defined _neonsm_included_
    #endinput
#endif

#include <ripext>

/**
 * Called when a checkpoint has been received from Neon.
 *
 * @param type      The data type to expect from the payload (i.e. the structure of the JSONObject).
 * @param payload   The raw data from the CheckpointResponse. The structure is defined by the type.
 * @note            The payload Handle is immediately closed after this function completes.
 * @noreturn
 */
typedef OnCheckpointCallback = function void (const char[] type, JSONObject payload);

/**
 * Creates a hook for when a checkpoint has been received from Neon.
 *
 * @param type      The data type to expect from the checkpoint.
 * @param callback  An OnCheckpointCallback function pointer.
 * @noreturn
 */
native void HookCheckpoint(const char[] type, OnCheckpointCallback callback);

/**
 * Removes a hook for when a checkpoint has been received from Neon.
 *
 * @param type      The data type to expect from the checkpoint.
 * @param callback  An OnCheckpointCallback function pointer.
 * @noreturn
 */
native void UnhookCheckpoint(const char[] type, OnCheckpointCallback callback);

/**
 * Creates a hook for when a checkpoint has been received from Neon.
 *
 * @param callback  An OnCheckpointCallback function pointer.
 * @noreturn
 */
native void HookCheckpointEx(OnCheckpointCallback callback);

/**
 * Removes a hook for when a checkpoint has been received from Neon.
 *
 * @param callback  An OnCheckpointCallback function pointer.
 * @noreturn
 */
native void UnhookCheckpointEx(OnCheckpointCallback callback);

/**
 * Called when a checkpoint has been received from Neon.
 *
 * @param type      The data type to expect from the payload (i.e. the structure of the JSONObject).
 * @param payload   The raw data from the CheckpointResponse. The structure is defined by the type.
 * @note            The payload Handle is immediately closed after this function completes.
 * @noreturn
 */
forward void OnCheckpoint(const char[] type, JSONObject payload);

/**
 * Sends an event to Neon via a POST request.
 *
 * @param type      The data type to expect from the payload (i.e. the structure of the JSONObject).
 * @param payload   The raw data for the EventRequest object. The structure is defined by the type.
 * @note            The payload Handle is immediately closed after this function completes.
 * @noreturn
 */
native void PostEvent(const char[] type, JSONObject payload);

public SharedPlugin __p1_neonsm =
{
    name = "neonsm",
    file = "neonsm.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __p1_neonsm_SetNTVOptional()
{
    MarkNativeAsOptional("HookCheckpoint");
    MarkNativeAsOptional("UnhookCheckpoint");
    MarkNativeAsOptional("HookCheckpointEx");
    MarkNativeAsOptional("UnhookCheckpointEx");
    MarkNativeAsOptional("PostEvent");
}
#endif
