using Godot;
using Godot.Collections;
using Array = Godot.Collections.Array;
using Dictionary = Godot.Collections.Dictionary;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

public partial class GDSync : Node
{
	private static Node GDSYNC;
	private static GDSync GDSYNC_SHARP;

	/// <summary>
	/// Emitted when the plugin successfully completes the connection and encryption handshake.
	/// This signal is emitted after using <see cref="StartMultiplayer"/>.
	/// If this is emitted it means you can use all other multiplayer functions.
	/// </summary>
	public static event Action Connected;
	/// <summary>
	/// Emitted if the connection handshake fails. This signal is emitted after using <see cref="StartMultiplayer"/>.
	/// </summary>
	/// <param name="error">The reason behind the failed connection attempt. See <see cref="CONNECTION_FAILED"/> for possible errors.</param>
	public static event Action<int> ConnectionFailed;
	/// <summary>
	/// Emitted when the client disconnects. Might be due to connectivity issues or when the server goes down.
	/// <para><b>IMPORTANT: The plugin does not automatically try to reconnect when a disconnect occurs.</b></para>
	/// </summary>
	public static event Action Disconnected;
	/// <summary>
	/// Emitted when the Client ID changes. This happens when using <see cref="StartMultiplayer"/> and might happen
	/// when using <see cref="JoinLobby"/>. This will NEVER happen while inside a lobby, so don't worry when
	/// using methods such as <see cref="SetGDSyncOwner"/>, <see cref="CallFuncOn"/>, etc.
	/// </summary>
	/// <param name="ownId">The new Client ID.</param>
	public static event Action<int> ClientIDChanged;
	/// <summary>
	/// Emitted if <see cref="CreateLobby"/> was successful.
	/// </summary>
	/// <param name="lobbyName">The name of the lobby that was created.</param>
	public static event Action<string> LobbyCreated;
	/// <summary>
	/// Emitted if <see cref="CreateLobby"/> fails.
	/// </summary>
	/// <param name="lobbyName">The name of the lobby that failed to create.</param>
	/// <param name="error">The reason why the creation failed. Check <see cref="LOBBY_CREATION_ERROR"/> for possible errors.</param>
	public static event Action<string, int> LobbyCreationFailed;
	/// <summary>
	/// Emitted if <see cref="ChangeLobbyName"/> was successful.
	/// </summary>
	/// <param name="lobbyName">The new lobby name.</param>
	public static event Action<string> LobbyNameChanged;
	/// <summary>
	/// Emitted if <see cref="ChangeLobbyName"/> fails.
	/// </summary>
	/// <param name="lobbyName">The new lobby name that failed.</param>
	/// <param name="error">The reason why the name change failed. Check <c>LOBBY_NAME_CHANGE_ERROR</c> for possible errors.</param>
	public static event Action<string, int> LobbyNameChangeFailed;
	/// <summary>
	/// Emitted when <see cref="JoinLobby"/> was successful.
	/// </summary>
	/// <param name="lobbyName">The name of the lobby that the player joined.</param>
	public static event Action<string> LobbyJoined;
	/// <summary>
	/// Emitted when <see cref="JoinLobby"/> failed.
	/// </summary>
	/// <param name="lobbyName">The name of the lobby that the player was unable to join.</param>
	/// <param name="error">The reason why the joining failed. Check <see cref="LOBBY_JOIN_ERROR"/> for possible errors.</param>
	public static event Action<string, int> LobbyJoinFailed;
	/// <summary>
	/// Emitted when any lobby data value is changed. Emitted after <see cref="SetLobbyData"/>.
	/// </summary>
	/// <param name="key">The key of the data that changed.</param>
	/// <param name="value">The new value. This will be null if the data was erased.</param>
	public static event Action<string, Variant> LobbyDataChanged;
	/// <summary>
	/// Emitted when any lobby tags value is changed. Emitted after <see cref="SetLobbyTag"/> and <see cref="EraseLobbyTag"/>.
	/// </summary>
	/// <param name="key">The key of the tag that changed.</param>
	/// <param name="value">The new value. This will be null if the tag was erased.</param>
	public static event Action<string, Variant> LobbyTagChanged;
	/// <summary>
	/// Emitted when a client joins the current lobby.
	/// <para><b>IMPORTANT: This is emitted for all clients, INCLUDING yourself when joining a lobby.</b></para>
	/// </summary>
	/// <param name="clientId">The id of the client that joined.</param>
	public static event Action<int> ClientJoined;
	/// <summary>
	/// Emitted when a client leaves the current lobby.
	/// <para><b>IMPORTANT: This is emitted for ALL clients, EXCLUDING yourself when leaving a lobby.</b></para>
	/// </summary>
	/// <param name="clientId">The id of the client that left.</param>
	public static event Action<int> ClientLeft;
	/// <summary>
	/// Emitted when a player uses <see cref="SetPlayerData"/>, <see cref="ErasePlayerData"/> or <see cref="SetPlayerUsername"/>.
	/// Player data is synchronized every second if it is altered.
	/// </summary>
	/// <param name="clientId">The id of the client whose data changed.</param>
	/// <param name="key">The key of the data that changed.</param>
	/// <param name="value">The new value.</param>
	public static event Action<int, string, Variant> PlayerDataChanged;
	/// <summary>
	/// Emitted as a result of <see cref="GetPublicLobbies"/>.
	/// </summary>
	/// <param name="lobbies">An array of all public lobbies and their publicly available data.</param>
	public static event Action<Array> LobbiesReceived;
	/// <summary>
	/// Emitted as a result of <see cref="GetPublicLobby"/>.
	/// </summary>
	/// <param name="lobby">A dictionary containing public lobby data. If the lobby was not found the dictionary will be empty.</param>
	public static event Action<Dictionary> LobbyReceived;
	/// <summary>
	/// Emitted once the server accepted a request made with <see cref="StartMatchmaking"/>.
	/// </summary>
	public static event Action MatchmakingStarted;
	/// <summary>
	/// Emitted whenever the progress of the active matchmaking request changes.
	/// </summary>
	/// <param name="status">The new status. See <see cref="MATCHMAKING_STATUS"/> for possible values.</param>
	/// <param name="details">Additional information about the current status, such as the amount of queued players.</param>
	public static event Action<int, Dictionary> MatchmakingStatusChanged;
	/// <summary>
	/// Emitted when matchmaking found a lobby. The plugin joins that lobby automatically,
	/// so <see cref="LobbyJoined"/> follows shortly after.
	/// </summary>
	/// <param name="lobbyName">The name of the lobby that was found.</param>
	public static event Action<string> MatchmakingMatchFound;
	/// <summary>
	/// Emitted when matchmaking fails.
	/// </summary>
	/// <param name="error">The reason why matchmaking failed. See <see cref="MATCHMAKING_ERROR"/> for possible errors.</param>
	public static event Action<int> MatchmakingFailed;
	/// <summary>
	/// Emitted after cancelling matchmaking using <see cref="CancelMatchmaking"/>.
	/// </summary>
	public static event Action MatchmakingCancelled;
	/// <summary>
	/// Emitted when the plugin failed to move this client to another server while joining a lobby.
	/// </summary>
	/// <param name="error">The reason why the switch failed. See <see cref="LOBBY_SWITCH_ERROR"/> for possible errors.</param>
	public static event Action<int> LobbySwitchFailed;
	/// <summary>
	/// Emitted when the host of the current lobby changes. This might happen if the current host leaves or disconnects.
	/// The server automatically decides which player is the host.
	/// <para>Being the host does not do anything by itself, but is something that can help you when developing authoritative code.</para>
	/// <para>The PropertySynchronizer class will also make use of this if told to do so in the inspector.</para>
	/// </summary>
	/// <param name="isHost">A boolean that indicates if you are the new host or not.</param>
	/// <param name="newHostId">The Client ID of the new host.</param>
	public static event Action<bool, int> HostChanged;
	/// <summary>
	/// Emitted when a time synchronized event is triggered. See <see cref="CreateSyncedEvent"/> for more information.
	/// </summary>
	/// <param name="eventName">The name of the event that has been triggered.</param>
	/// <param name="parameters">Any parameters bound to the event.</param>
	public static event Action<string, Array> SyncedEventTriggered;
	/// <summary>
	/// Emitted when <see cref="ChangeScene"/> is called.
	/// </summary>
	/// <param name="scenePath">The path of the scene.</param>
	public static event Action<string> ChangeSceneCalled;
	/// <summary>
	/// Emitted right before the scene is switched when using <see cref="ChangeScene"/>.
	/// </summary>
	/// <param name="scenePath">The path of the scene.</param>
	public static event Action<string> ChangeSceneSuccess;
	/// <summary>
	/// Emitted when a scene change failed for any of the clients in the lobby.
	/// This can be because of an invalid path, failing to load the resource, etc.
	/// </summary>
	/// <param name="scenePath">The path of the scene.</param>
	public static event Action<string> ChangeSceneFailed;
	/// <summary>
	/// Emitted when the player tries to join a friend on Steam.
	/// </summary>
	/// <param name="lobbyName">The name of lobby the player is trying to join.</param>
	/// <param name="hasPassword">If the lobby has a password or not.</param>
	public static event Action<string, bool> SteamJoinRequest;
	/// <summary>
	/// Emitted if you get kicked from the current lobby.
	/// </summary>
	public static event Action Kicked;
	/// <summary>
	/// Emitted if you get kicked from the current lobby, including the reason supplied by the host.
	/// </summary>
	public static event Action<string> KickedWithReason;
	/// <summary>
	/// Emitted after successfully logging into a GD-Sync account.
	/// </summary>
	public static event Action<string> AccountLoggedIn;
	/// <summary>
	/// Emitted after logging out of a GD-Sync account.
	/// </summary>
	public static event Action AccountLoggedOut;

	public override void _Ready()
	{
		GDSYNC = GetNode("/root/GDSync");
		GDSYNC_SHARP = this;

		GDSYNC.Connect("connected", Callable.From(() => Connected?.Invoke()));
		GDSYNC.Connect("connection_failed", Callable.From((int error) => ConnectionFailed?.Invoke(error)));
		GDSYNC.Connect("disconnected", Callable.From(() => Disconnected?.Invoke()));
		GDSYNC.Connect("client_id_changed", Callable.From((int ownID) => ClientIDChanged?.Invoke(ownID)));
		GDSYNC.Connect("lobby_created", Callable.From((string lobbyName) => LobbyCreated?.Invoke(lobbyName)));
		GDSYNC.Connect("lobby_creation_failed", Callable.From((string lobbyName, int error) => LobbyCreationFailed?.Invoke(lobbyName, error)));
		GDSYNC.Connect("lobby_name_changed", Callable.From((string lobbyName) => LobbyNameChanged?.Invoke(lobbyName)));
		GDSYNC.Connect("lobby_name_change_failed", Callable.From((string lobbyName, int error) => LobbyNameChangeFailed?.Invoke(lobbyName, error)));
		GDSYNC.Connect("lobby_joined", Callable.From((string lobbyName) => LobbyJoined?.Invoke(lobbyName)));
		GDSYNC.Connect("lobby_join_failed", Callable.From((string lobbyName, int error) => LobbyJoinFailed?.Invoke(lobbyName, error)));
		GDSYNC.Connect("lobby_data_changed", Callable.From((string key, Variant value) => LobbyDataChanged?.Invoke(key, value)));
		GDSYNC.Connect("lobby_tag_changed", Callable.From((string key, Variant value) => LobbyTagChanged?.Invoke(key, value)));
		GDSYNC.Connect("client_joined", Callable.From((int clientID) => ClientJoined?.Invoke(clientID)));
		GDSYNC.Connect("client_left", Callable.From((int clientID) => ClientLeft?.Invoke(clientID)));
		GDSYNC.Connect("player_data_changed", Callable.From((int clientID, string key, Variant value) => PlayerDataChanged?.Invoke(clientID, key, value)));
		GDSYNC.Connect("kicked", Callable.From((string reason) =>
		{
			Kicked?.Invoke();
			KickedWithReason?.Invoke(reason);
		}));
		GDSYNC.Connect("lobbies_received", Callable.From((Array lobbies) => LobbiesReceived?.Invoke(lobbies)));
		GDSYNC.Connect("lobby_received", Callable.From((Dictionary lobby) => LobbyReceived?.Invoke(lobby)));
		GDSYNC.Connect("matchmaking_started", Callable.From(() => MatchmakingStarted?.Invoke()));
		GDSYNC.Connect("matchmaking_status_changed", Callable.From((int status, Dictionary details) => MatchmakingStatusChanged?.Invoke(status, details)));
		GDSYNC.Connect("matchmaking_match_found", Callable.From((string lobbyName) => MatchmakingMatchFound?.Invoke(lobbyName)));
		GDSYNC.Connect("matchmaking_failed", Callable.From((int error) => MatchmakingFailed?.Invoke(error)));
		GDSYNC.Connect("matchmaking_cancelled", Callable.From(() => MatchmakingCancelled?.Invoke()));
		GDSYNC.Connect("lobby_switch_failed", Callable.From((int error) => LobbySwitchFailed?.Invoke(error)));
		GDSYNC.Connect("host_changed", Callable.From((bool isHost, int hostID) => HostChanged?.Invoke(isHost, hostID)));
		GDSYNC.Connect("synced_event_triggered", Callable.From((string eventName, Array parameters) => SyncedEventTriggered?.Invoke(eventName, parameters)));
		GDSYNC.Connect("change_scene_called", Callable.From((string scenePath) => ChangeSceneCalled?.Invoke(scenePath)));
		GDSYNC.Connect("change_scene_success", Callable.From((string scenePath) => ChangeSceneSuccess?.Invoke(scenePath)));
		GDSYNC.Connect("change_scene_failed", Callable.From((string scenePath) => ChangeSceneFailed?.Invoke(scenePath)));
		GDSYNC.Connect("steam_join_request", Callable.From((string lobbyName, bool hasPassword) => SteamJoinRequest?.Invoke(lobbyName, hasPassword)));
		GDSYNC.Connect("account_logged_in", Callable.From((string username) => AccountLoggedIn?.Invoke(username)));
		GDSYNC.Connect("account_logged_out", Callable.From(() => AccountLoggedOut?.Invoke()));
	}




	// General functions -----------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region General Functions

	/// <summary>
	/// Starts the GD-Sync plugin by connecting to a server. If successful, <see cref="Connected"/> will be emitted.
	/// If not, <see cref="ConnectionFailed"/> will be emitted.
	/// </summary>
	public static void StartMultiplayer()
	{
		GDSYNC.Call("start_multiplayer");
	}

	/// <summary>
	/// Starts the GD-Sync plugin locally. This will allow for local peer-to-peer connections but will disable features
	/// such as database access and automatic host switching. Local mode also disables some optimization features
	/// related to networking.
	/// <para>Using local multiplayer does not require an account or API keys and does not use any data transfer.</para>
	/// <para>If successful, <see cref="Connected"/> will be emitted. If not, <see cref="ConnectionFailed"/> will be emitted.</para>
	/// </summary>
	public static void StartLocalMultiplayer()
	{
		GDSYNC.Call("start_local_multiplayer");
	}

	/// <summary>
	/// Stops the GD-Sync plugin. This will break any existing connections and disable the multiplayer.
	/// </summary>
	public static void StopMultiplayer()
	{
		GDSYNC.Call("stop_multiplayer");
	}

	/// <summary>
	/// An alternative for get_tree().quit(). Only use if you log into a GD-Sync account using <see cref="Login(string, string, float)"/>.
	/// When quitting while logged in the plugin makes some callbacks to the server to update information like
	/// your friend status.
	/// </summary>
	public static void Quit()
	{
		GDSYNC.Call("quit");
	}

	/// <summary>
	/// Returns true if the plugin is connected to a server. Returns false if there is no active connection.
	/// </summary>
	/// <returns>True if connected to a server, false otherwise.</returns>
	public static bool IsActive()
	{
		return (bool)GDSYNC.Call("is_active");
	}

	/// <summary>
	/// Returns your own Client ID. Returns -1 if you are not connected to a server.
	/// </summary>
	/// <returns>Your Client ID, or -1 if not connected.</returns>
	public static int GetClientID()
	{
		return (int)GDSYNC.Call("get_client_id");
	}

	/// <summary>
	/// Measures and returns the ping between this client and another client. This only measures network travel time for the message. Useful for checking raw network latency between clients.
	/// If the returned float is -1, the ping calculation failed.
	/// </summary>
	/// <param name="clientId">The Client ID to measure ping to.</param>
	/// <returns>The ping in seconds, or -1 if the calculation failed.</returns>
	public static async Task<float> GetClientPing(int clientId)
	{
		var result = await CallAwaited("get_client_ping", new Array { clientId });
		return CastToFloat(result[0]);
	}

	/// <summary>
	/// Measures and returns the perceived ping between this client and another client. This includes network travel time plus additional delay caused by frame timing. Useful for estimating player-visible latency.
	/// If the returned float is -1, the ping calculation failed.
	/// </summary>
	/// <param name="clientId">The Client ID to measure perceived ping to.</param>
	/// <returns>The perceived ping in seconds, or -1 if the calculation failed.</returns>
	public static async Task<float> GetClientPerceivedPing(int clientId)
	{
		var result = await CallAwaited("get_client_perceived_ping", new Array { clientId });
		return CastToFloat(result[0]);
	}

	/// <summary>
	/// Sets local artificial latency for debugging. The delay is applied to both outgoing and incoming packets.
	/// Set to 0 to disable.
	/// </summary>
	/// <param name="latencyMs">The artificial latency in milliseconds.</param>
	public static void SetArtificialLatency(int latencyMs)
	{
		GDSYNC.Call("set_artificial_latency", latencyMs);
	}

	/// <summary>
	/// Returns the currently configured local artificial latency in milliseconds.
	/// </summary>
	public static int GetArtificialLatency()
	{
		return (int)GDSYNC.Call("get_artificial_latency");
	}

	/// <summary>
	/// Returns the Client ID of the last client to perform a remote function call on this client.
	/// Useful for knowing where a remote function call came from.
	/// Returns -1 if nobody performed a remote function call yet.
	/// </summary>
	/// <returns>The Client ID of the sender, or -1 if no remote call was received.</returns>
	public static int GetSenderID()
	{
		return (int)GDSYNC.Call("get_sender_id");
	}

	/// <summary>
	/// Returns whether you are the host of the lobby you are in.
	/// </summary>
	/// <returns>True if you are the host, false otherwise.</returns>
	public static bool IsHost()
	{
		return (bool)GDSYNC.Call("is_host");
	}

	/// <summary>
	/// Returns the Client ID of the host of the current lobby you are in. Returns -1 if you are not in a lobby.
	/// </summary>
	/// <returns>The Client ID of the host, or -1 if not in a lobby.</returns>
	public static int GetHost()
	{
		return (int)GDSYNC.Call("get_host");
	}

	/// <summary>
	/// Manually sets the host of the current lobby. Can only be used by the current host. This function does not work in local multiplayer.
	/// </summary>
	/// <param name="clientId">The Client ID of the new host.</param>
	public static void SetHost(int clientId)
	{
		GDSYNC.Call("set_host", clientId);
	}

	/// <summary>
	/// Synchronizes a variable on a Object across all other clients in the current lobby.
	/// Make sure that the variable is exposed using <see cref="ExposeVar(GodotObject, string)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="target">The Object you want to synchronize a variable on.</param>
	/// <param name="variableName">The name of the variable you want to synchronize.</param>
	/// <param name="reliable">If reliable, if the request fails to deliver it will reattempt until successful.
	/// This may introduce more latency. Use unreliable if the sync happens frequently (such as the position of a Node) for lower latency.</param>
	public static void SyncVar(GodotObject target, string variableName, bool reliable = true)
	{
		GDSYNC.Call("sync_var", target, variableName, reliable);
	}

	/// <summary>
	/// Synchronizes a variable on a Object to a specific client in the current lobby.
	/// Make sure that the variable is exposed using <see cref="ExposeVar(GodotObject, string)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="clientId">The Client ID of the client you want to synchronize to.</param>
	/// <param name="target">The Object you want to synchronize a variable on.</param>
	/// <param name="variableName">The name of the variable you want to synchronize.</param>
	/// <param name="reliable">If reliable, if the request fails to deliver it will reattempt until successful.
	/// This may introduce more latency. Use unreliable if the sync happens frequently (such as the position of a Node) for lower latency.</param>
	public static void SyncVarOn(int clientId, GodotObject target, string variableName, bool reliable = true)
	{
		GDSYNC.Call("sync_var_on", clientId, target, variableName, reliable);
	}

	/// <summary>
	/// Synchronizes a variable to clients interested in the nearest InterestObject.
	/// Falls back to <see cref="SyncVar"/> when no InterestObject is found.
	/// </summary>
	public static void SyncVarRelevant(GodotObject target, string variableName, bool reliable = true)
	{
		GDSYNC.Call("sync_var_relevant", target, variableName, reliable);
	}

	/// <summary>
	/// Synchronizes a variable to a specific client only when that client is interested in the nearest InterestObject.
	/// Falls back to <see cref="SyncVarOn"/> when no InterestObject is found.
	/// </summary>
	public static void SyncVarOnRelevant(int clientId, GodotObject target, string variableName, bool reliable = true)
	{
		GDSYNC.Call("sync_var_on_relevant", clientId, target, variableName, reliable);
	}

	/// <summary>
	/// Calls a function on a Node or Resource on all other clients in the current lobby, excluding yourself. If the request fails to deliver it will reattempt until successful.
	/// Make sure that the function is exposed using <see cref="ExposeFunction(Callable)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="callable">The function that you want to call.</param>
	/// <param name="parameters">The parameters of the function you are calling (if it has any).</param>
	public static void CallFunc(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>
	/// Calls a function on a Node or Resource on all other clients in the current lobby, excluding yourself. If the request fails to deliver it will not reattempt, may result in lower latency compared to the regular version.
	/// Make sure that the function is exposed using <see cref="ExposeFunction(Callable)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="callable">The function that you want to call.</param>
	/// <param name="parameters">The parameters of the function you are calling (if it has any).</param>
	public static void CallFuncUnreliable(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_unreliable", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>
	/// Calls a function on a Node or Resource on a specific client in the current lobby. If the request fails to deliver it will reattempt until successful.
	/// Make sure that the function is exposed using <see cref="ExposeFunction(Callable)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="clientId">The Client ID of the client you want to call the function on.</param>
	/// <param name="callable">The function that you want to call.</param>
	/// <param name="parameters">The parameters of the function you are calling (if it has any).</param>
	public static void CallFuncOn(int clientId, Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_on", BuildCallArguments(new Array() { clientId, callable }, parameters));
	}

	/// <summary>
	/// Calls a function on a Node or Resource on a specific client in the current lobby. If the request fails to deliver it will not reattempt, may result in lower latency compared to the regular version.
	/// Make sure that the function is exposed using <see cref="ExposeFunction(Callable)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="clientId">The Client ID of the client you want to call the function on.</param>
	/// <param name="callable">The function that you want to call.</param>
	/// <param name="parameters">Optional parameters.</param>
	public static void CallFuncOnUnreliable(int clientId, Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_on_unreliable", BuildCallArguments(new Array() { clientId, callable }, parameters));
	}

	/// <summary>
	/// Calls a function on a Node or Resource on all clients in the current lobby, including yourself. If the request fails to deliver it will reattempt until successful.
	/// Make sure that the function is exposed using <see cref="ExposeFunction(Callable)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="callable">The function that you want to call.</param>
	/// <param name="parameters">The parameters of the function you are calling (if it has any).</param>
	public static void CallFuncAll(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_all", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>
	/// Calls a function on a Node or Resource on all clients in the current lobby, including yourself. If the request fails to deliver it will not reattempt, may result in lower latency compared to the regular version.
	/// Make sure that the function is exposed using <see cref="ExposeFunction(Callable)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="callable">The function that you want to call.</param>
	/// <param name="parameters">The parameters of the function you are calling (if it has any).</param>
	public static void CallFuncAllUnreliable(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_all_unreliable", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>Calls a function reliably on interested clients, excluding yourself.</summary>
	public static void CallFuncRelevant(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_relevant", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>Calls a function unreliably on interested clients, excluding yourself.</summary>
	public static void CallFuncRelevantUnreliable(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_relevant_unreliable", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>Calls a function reliably on a specific client only when that client is interested.</summary>
	public static void CallFuncOnRelevant(int clientId, Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_on_relevant", BuildCallArguments(new Array() { clientId, callable }, parameters));
	}

	/// <summary>Calls a function unreliably on a specific client only when that client is interested.</summary>
	public static void CallFuncOnRelevantUnreliable(int clientId, Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_on_relevant_unreliable", BuildCallArguments(new Array() { clientId, callable }, parameters));
	}

	/// <summary>Calls a function reliably locally and on all interested clients.</summary>
	public static void CallFuncAllRelevant(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_all_relevant", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>Calls a function unreliably locally and on all interested clients.</summary>
	public static void CallFuncAllRelevantUnreliable(Callable callable, params Variant[] parameters)
	{
		GDSYNC.Callv("call_func_all_relevant_unreliable", BuildCallArguments(new Array() { callable }, parameters));
	}

	/// <summary>
	/// Emits a signal on a Node or Resource on all other clients in the current lobby, excluding yourself.
	/// Make sure that the signal is exposed using <see cref="ExposeSignal(Signal)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="targetSignal">The signal you want to emit.</param>
	/// <param name="parameters">The parameters of the signal you are emitting (if it has any).</param>
	public static void EmitSignalRemote(Signal targetSignal, params Variant[] parameters)
	{
		GDSYNC.Callv("emit_signal_remote", BuildCallArguments(new Array() { targetSignal }, parameters));
	}

	/// <summary>
	/// Emits a signal on a Node or Resource on specific client in the current lobby.
	/// Make sure that the signal is exposed using <see cref="ExposeSignal(Signal)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="clientId">The Client ID of the client you want to emit the signal on.</param>
	/// <param name="targetSignal">The signal you want to emit.</param>
	/// <param name="parameters">The parameters of the signal you are emitting (if it has any).</param>
	public static void EmitSignalRemoteOn(int clientId, Signal targetSignal, params Variant[] parameters)
	{
		GDSYNC.Callv("emit_signal_remote_on", BuildCallArguments(new Array() { clientId, targetSignal }, parameters));
	}

	/// <summary>
	/// Emits a signal on a Node or Resource on all other clients in the current lobby, including yourself.
	/// Make sure that the signal is exposed using <see cref="ExposeSignal(Signal)"/> or <see cref="ExposeNode(Node)"/>/<see cref="ExposeResource(RefCounted)"/>.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="targetSignal">The signal you want to emit.</param>
	/// <param name="parameters">The parameters of the signal you are emitting (if it has any).</param>
	public static void EmitSignalRemoteAll(Signal targetSignal, params Variant[] parameters)
	{
		GDSYNC.Callv("emit_signal_remote_all", BuildCallArguments(new Array() { targetSignal }, parameters));
	}

	/// <summary>Emits a signal on interested clients, excluding yourself.</summary>
	public static void EmitSignalRemoteRelevant(Signal targetSignal, params Variant[] parameters)
	{
		GDSYNC.Callv("emit_signal_remote_relevant", BuildCallArguments(new Array() { targetSignal }, parameters));
	}

	/// <summary>Emits a signal on a specific client only when that client is interested.</summary>
	public static void EmitSignalRemoteOnRelevant(int clientId, Signal targetSignal, params Variant[] parameters)
	{
		GDSYNC.Callv("emit_signal_remote_on_relevant", BuildCallArguments(new Array() { clientId, targetSignal }, parameters));
	}

	/// <summary>Emits a signal locally and on all interested clients.</summary>
	public static void EmitSignalRemoteAllRelevant(Signal targetSignal, params Variant[] parameters)
	{
		GDSYNC.Callv("emit_signal_remote_all_relevant", BuildCallArguments(new Array() { targetSignal }, parameters));
	}

	/// <summary>
	/// Instantiates a Node on all clients in the current lobby.
	/// <para><b>IMPORTANT:</b> Make sure the NodePath of the parent matches up on all clients.</para>
	/// </summary>
	/// <param name="scene">The PackedScene you want to instantiate.</param>
	/// <param name="parent">The parent/location of where you want to instantiate the Node.</param>
	/// <param name="syncStartingChanges">If enabled, any changes made to the root Node of the instantiated scene
	/// within the same frame will automatically be synchronized.</param>
	/// <param name="excludedProperties">Names of properties you want to exclude from sync_starting_changes.</param>
	/// <param name="replicateOnJoin">If enabled, the instantiated Node will be replicated on clients that
	/// join the lobby later on.</param>
	/// <returns>The instantiated Node.</returns>
	public static Node MultiplayerInstantiate(PackedScene scene, Node parent, bool syncStartingChanges = true, string[] excludedProperties = null, bool replicateOnJoin = true)
	{
		return (Node)GDSYNC.Call(
			"multiplayer_instantiate",
			scene,
			parent,
			syncStartingChanges,
			excludedProperties ?? new string[0],
			replicateOnJoin
		);
	}

	/// <summary>
	/// Queues a Node for freeing on all clients in the current lobby.
	/// </summary>
	/// <param name="node">The Node to queue for freeing.</param>
	public static void MultiplayerQueueFree(Node node)
	{
		GDSYNC.Call("multiplayer_queue_free", node);
	}

	/// <summary>
	/// Returns a float which contains the current multiplayer time. This time is synchronized across clients in
	/// the same lobby. Can be used for time-based events. See <see cref="CreateSyncedEvent"/> for creating
	/// time-based triggers.
	/// <para><b>IMPORTANT:</b> It may take up to a second for the time to synchronize after just joining a lobby.</para>
	/// </summary>
	/// <returns>The current synchronized multiplayer time.</returns>
	public static float GetMultiplayerTime()
	{
		return CastToFloat(GDSYNC.Call("get_multiplayer_time"));
	}

	/// <summary>
	/// Create a time-based event that triggers after a delay. GD-Sync will attempt to trigger this event
	/// on all clients at the same time, regardless of the latency between clients. Useful for creating
	/// time-critical events or mechanics. After the delay, <see cref="SyncedEventTriggered"/> is emitted.
	/// <para><b>IMPORTANT:</b> If the given delay is shorter than the latency between two clients, the
	/// event trigger might be delayed. It is recommended to always use a delay >= 1 second.</para>
	/// </summary>
	/// <param name="eventName">The name of the event. Queued events can share the same name.</param>
	/// <param name="delay">The delay in seconds after which the event should be triggered.</param>
	/// <param name="parameters">Any parameters which should be bound to the event.</param>
	public static void CreateSyncedEvent(string eventName, float delay = 1.0f, Array parameters = null)
	{
		GDSYNC.Call("synced_event_create", eventName, delay, parameters ?? new Array());
	}

	/// <summary>
	/// Changes the current scene for all clients. Waits with changing until the scene has fully loaded on all clients.
	/// Emits <see cref="ChangeSceneCalled"/> when a scene change is requested, <see cref="ChangeSceneSuccess"/> when it succeeds,
	/// and <see cref="ChangeSceneFailed"/> if it fails on any client.
	/// </summary>
	/// <param name="scenePath">The resource path of the scene.</param>
	public static void ChangeScene(string scenePath)
	{
		GDSYNC.Call("change_scene", scenePath);
	}

	private static Array BuildCallArguments(Array prefix, Variant[] parameters)
	{
		if (parameters == null || parameters.Length == 0)
		{
			return prefix;
		}

		var args = new Array();
		foreach (var item in prefix)
		{
			args.Add(item);
		}

		foreach (var parameter in parameters)
		{
			args.Add(parameter);
		}

		return args;
	}

	private static float CastToFloat(object value)
	{
		return value is float f ? f : Convert.ToSingle(value);
	}

	private static async Task<Variant[]> CallAwaited(string method, Array args)
	{
		Variant callResult = GDSYNC.Callv(method, args);
		if (callResult.VariantType != Variant.Type.Object)
		{
			return new Variant[] { callResult };
		}

		var asyncRequest = callResult.AsGodotObject();
		if (asyncRequest == null || !asyncRequest.HasSignal("completed"))
		{
			return new Variant[] { callResult };
		}

		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return result;
	}

#endregion






	// Security & safety functions -------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Security & Safety Functions

	/// <summary>
	/// If set to true, all remote function calls and variable synchronization requests will be blocked by default.
	/// Only functions, variables and Nodes that are exposed using <see cref="ExposeFunction(Callable)"/>, <see cref="ExposeVar(GodotObject, string)"/> and <see cref="ExposeNode(Node)"/>
	/// may be accessed remotely. This setting can also be found in the configuration menu.
	/// <para>We STRONGLY recommend keeping this enabled at all times. Disabling it may introduce security risks.</para>
	/// </summary>
	/// <param name="protectionEnabled">If protected mode should be enabled or disabled.</param>
	public static void SetProtectionMode(bool protectionEnabled)
	{
		GDSYNC.Call("set_protection_mode", protectionEnabled);
	}

	/// <summary>
	/// Allows you to register a resource with a unique ID so that GD-Sync may access it remotely.
	/// </summary>
	/// <param name="resource">The resource you want to register.</param>
	/// <param name="id">The ID you want to assign to it.</param>
	public static void RegisterResource(RefCounted resource, string id)
	{
		GDSYNC.Call("register_resource", resource, id);
	}

	/// <summary>
	/// Allows you to deregister a previously registered resource.
	/// </summary>
	/// <param name="resource">The resource you want to deregister.</param>
	public static void DeregisterResource(RefCounted resource)
	{
		GDSYNC.Call("deregister_resource", resource);
	}

	/// <summary>
	/// Exposes a Node so that all <see cref="CallFunc(Callable, Variant[])"/>, <see cref="CallFuncOn(int, Callable, Variant[])"/>, <see cref="SyncVar(GodotObject, string, bool)"/> and <see cref="SyncVarOn(int, GodotObject, string, bool)"/> will succeed.
	/// Only use if the Node and its script contain non-destructive functions.
	/// <para><b>IMPORTANT:</b> Make sure the NodePath of the Node matches up on all clients.</para>
	/// </summary>
	/// <param name="node">The Node you want to expose.</param>
	public static void ExposeNode(Node node)
	{
		GDSYNC.Call("expose_node", node);
	}

	/// <summary>
	/// Hides a Node so that all <see cref="CallFunc(Callable, Variant[])"/>, <see cref="CallFuncOn(int, Callable, Variant[])"/>, <see cref="SyncVar(GodotObject, string, bool)"/> and <see cref="SyncVarOn(int, GodotObject, string, bool)"/> will fail.
	/// This will not revert <see cref="ExposeFunction(Callable)"/> and <see cref="ExposeVar(GodotObject, string)"/>.
	/// <para><b>IMPORTANT:</b> Make sure the NodePath of the Node matches up on all clients.</para>
	/// </summary>
	/// <param name="node">The Node you want to hide.</param>
	public static void HideNode(Node node)
	{
		GDSYNC.Call("hide_node", node);
	}

	/// <summary>
	/// Exposes a Resource so that all <see cref="CallFunc(Callable, Variant[])"/>, <see cref="CallFuncOn(int, Callable, Variant[])"/>, <see cref="SyncVar(GodotObject, string, bool)"/> and <see cref="SyncVarOn(int, GodotObject, string, bool)"/> will succeed.
	/// Only use if the Resource and its script contain non-destructive functions.
	/// <para><b>IMPORTANT:</b> Make sure the Resource has been registered using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="resource">The Resource you want to expose.</param>
	public static void ExposeResource(RefCounted resource)
	{
		GDSYNC.Call("expose_resource", resource);
	}

	/// <summary>
	/// Hides a Resource so that all <see cref="CallFunc(Callable, Variant[])"/>, <see cref="CallFuncOn(int, Callable, Variant[])"/>, <see cref="SyncVar(GodotObject, string, bool)"/> and <see cref="SyncVarOn(int, GodotObject, string, bool)"/> will fail.
	/// This will not revert <see cref="ExposeFunction(Callable)"/> and <see cref="ExposeVar(GodotObject, string)"/>.
	/// <para><b>IMPORTANT:</b> Make sure the Resource has been registered using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="resource">The Resource you want to hide.</param>
	public static void HideResource(RefCounted resource)
	{
		GDSYNC.Call("hide_resource", resource);
	}

	/// <summary>
	/// Exposes a function so that <see cref="CallFunc(Callable, Variant[])"/> and <see cref="CallFuncOn(int, Callable, Variant[])"/> will succeed.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="callable">The function you want to expose.</param>
	public static void ExposeFunction(Callable callable)
	{
		ExposeFunction(callable, EXPOSE_PERMISSION.ANYONE);
	}

	/// <summary>
	/// Exposes a function with a specific remote access permission.
	/// </summary>
	/// <param name="callable">The function you want to expose.</param>
	/// <param name="permission">Who may call the exposed function.</param>
	public static void ExposeFunction(Callable callable, EXPOSE_PERMISSION permission)
	{
		GDSYNC.Call("expose_func", callable, (int)permission);
	}

	/// <summary>
	/// Hides a function so that <see cref="CallFunc(Callable, Variant[])"/> and <see cref="CallFuncOn(int, Callable, Variant[])"/> will fail.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="callable">The function you want to hide.</param>
	public static void HideFunction(Callable callable)
	{
		GDSYNC.Call("hide_func", callable);
	}

	/// <summary>
	/// Exposes a signal so that <see cref="EmitSignalRemote(Signal, Variant[])"/>, <see cref="EmitSignalRemoteOn(int, Signal, Variant[])"/> and <see cref="EmitSignalRemoteAll(Signal, Variant[])"/> will succeed.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="signal">The signal you want to expose.</param>
	public static void ExposeSignal(Signal signal)
	{
		ExposeSignal(signal, EXPOSE_PERMISSION.ANYONE);
	}

	/// <summary>
	/// Exposes a signal with a specific remote access permission.
	/// </summary>
	/// <param name="signal">The signal you want to expose.</param>
	/// <param name="permission">Who may emit the exposed signal.</param>
	public static void ExposeSignal(Signal signal, EXPOSE_PERMISSION permission)
	{
		GDSYNC.Call("expose_signal", signal, (int)permission);
	}

	/// <summary>
	/// Hides a signal so that <see cref="EmitSignalRemote(Signal, Variant[])"/>, <see cref="EmitSignalRemoteOn(int, Signal, Variant[])"/> and <see cref="EmitSignalRemoteAll(Signal, Variant[])"/> will fail.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="signal">The signal you want to hide.</param>
	public static void HideSignal(Signal signal)
	{
		GDSYNC.Call("hide_signal", signal);
	}

	/// <summary>
	/// Exposes a variable so that <see cref="SyncVar(GodotObject, string, bool)"/> and <see cref="SyncVarOn(int, GodotObject, string, bool)"/> will succeed.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="target">The Object on which you want to expose the variable.</param>
	/// <param name="variableName">The name of the variable you want to expose.</param>
	public static void ExposeVar(GodotObject target, string variableName)
	{
		ExposeVar(target, variableName, EXPOSE_PERMISSION.ANYONE);
	}

	/// <summary>
	/// Exposes a variable with a specific remote access permission.
	/// </summary>
	/// <param name="target">The Object on which you want to expose the variable.</param>
	/// <param name="variableName">The name of the variable you want to expose.</param>
	/// <param name="permission">Who may synchronize the exposed variable.</param>
	public static void ExposeVar(GodotObject target, string variableName, EXPOSE_PERMISSION permission)
	{
		GDSYNC.Call("expose_var", target, variableName, (int)permission);
	}

	/// <summary>
	/// Hides a variable so that <see cref="SyncVar(GodotObject, string, bool)"/> and <see cref="SyncVarOn(int, GodotObject, string, bool)"/> will fail.
	/// <para><b>IMPORTANT:</b> For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using <see cref="RegisterResource(RefCounted, string)"/>.</para>
	/// </summary>
	/// <param name="target">The Object on which you want to hide the variable.</param>
	/// <param name="variableName">The name of the variable you want to hide.</param>
	public static void HideVar(GodotObject target, string variableName)
	{
		GDSYNC.Call("hide_var", target, variableName);
	}
	#endregion

	// Steam Integration -----------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Steam Integration

	/// <summary>
	/// Returns true if the GodotSteam plugin is installed.
	/// </summary>
	/// <returns>True if the GodotSteam plugin is installed, false otherwise.</returns>
	public static bool SteamIntegrationEnabled()
	{
		return (bool)GDSYNC.Call("steam_integration_enabled");
	}

	/// <summary>
	/// Links your GD-Sync account with your Steam account. This will allow you to log into your GD-Sync account
	/// using your active Steam session.
	/// </summary>
	/// <returns>The result of the request as LINK_STEAM_ACCOUNT_RESPONSE_CODE.</returns>
	public static async Task<LINK_STEAM_ACCOUNT_RESPONSE_CODE> SteamLinkAccount()
	{
		var result = await CallAwaited("steam_link_account", new Array());
		return (LINK_STEAM_ACCOUNT_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Unlinks your GD-Sync account from Steam.
	/// </summary>
	/// <returns>The result of the request as UNLINK_STEAM_ACCOUNT_RESPONSE_CODE.</returns>
	public static async Task<UNLINK_STEAM_ACCOUNT_RESPONSE_CODE> SteamUnlinkAccount()
	{
		var result = await CallAwaited("steam_unlink_account", new Array());
		return (UNLINK_STEAM_ACCOUNT_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Logs into your GD-Sync account using the active Steam session.
	/// Only works if a Steam account has been linked.
	/// Returns a Dictionary with the format seen below and the STEAM_LOGIN_RESPONSE_CODE response code.
	/// If the user is banned, it will include the "Banned" key, which contains the unix timestamp when the ban will
	/// expire. If the ban is permanent, the value will be -1.
	/// </summary>
	/// <param name="validTime">The time in seconds how long the login session is valid.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "BanTime": 1719973379}</returns>
	public static async Task<Dictionary> SteamLogin(float validTime = 86400)
	{
		var result = await CallAwaited("steam_login", new Array { validTime });
		return (Dictionary)result[0];
	}

	#endregion


	// Node ownership --------------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Node Ownership

	/// <summary>
	/// Sets the owner of a Node. Node ownership is recursive and will apply to all children.
	/// Being the owner of a Node does not do anything by itself, but is useful when writing certain scripts.
	/// For example, when you are re-using your player scene for all players, you can only execute the keyboard inputs on
	/// the player of which you are the owner.
	/// <para>The PropertySynchronizer class will also make use of this if told to do so in the inspector.</para>
	/// <para><b>IMPORTANT:</b> Make sure the NodePath of the Node matches up on all clients.</para>
	/// </summary>
	/// <param name="node">The Node on which you want to assign ownership to.</param>
	/// <param name="owner">The client ID of the new owner.</param>
	public static void SetGDSyncOwner(Node node, int owner)
	{
		GDSYNC.Call("set_gdsync_owner", node, owner);
	}

	/// <summary>
	/// Clears the owner of a Node. Node ownership is recursive and will be removed on all children.
	/// <para><b>IMPORTANT:</b> Make sure the NodePath of the Node matches up on all clients.</para>
	/// </summary>
	/// <param name="node">The Node on which you want to clear ownership.</param>
	public static void ClearGDSyncOwner(Node node)
	{
		GDSYNC.Call("clear_gdsync_owner", node);
	}

	/// <summary>
	/// Returns the Client ID of the client that has ownership of the Node. Returns -1 if there is no owner.
	/// </summary>
	/// <param name="node">The Node from which you want to retrieve the owner.</param>
	/// <returns>The Client ID of the owner, or -1 if there is no owner.</returns>
	public static int GetGDSyncOwner(Node node)
	{
		return (int)GDSYNC.Call("get_gdsync_owner", node);
	}

	/// <summary>
	/// Returns true if you are the owner of the Node in question. Returns false if you are not the owner or when there is no owner.
	/// </summary>
	/// <param name="node">The Node on which you want to perform the ownership check.</param>
	/// <returns>True if you are the owner, false otherwise.</returns>
	public static bool IsGDSyncOwner(Node node)
	{
		return (bool)GDSYNC.Call("is_gdsync_owner", node);
	}

	/// <summary>
	/// Connects up a signal so that a specific function gets called if the owner of the Node changes.
	/// The function must have one parameter which is the Client ID of the new owner.
	/// The Client ID will be -1 if the Node doesn't have an owner anymore.
	/// </summary>
	/// <param name="node">The Node of which you want to monitor ownership.</param>
	/// <param name="callable">The function that should get called if the owner changes.</param>
	public static void ConnectGDSyncOwnerChanged(Node node, Callable callable)
	{
		GDSYNC.Call("connect_gdsync_owner_changed", node, callable);
	}

	/// <summary>
	/// Disconnects a function from the ownership signal created in <see cref="ConnectGDSyncOwnerChanged(Node, Callable)"/>.
	/// </summary>
	/// <param name="node">The Node of which you want to disconnect ownership monitoring.</param>
	/// <param name="callable">The function that should get disconnected.</param>
	public static void DisconnectGDSyncOwnerChanged(Node node, Callable callable)
	{
		GDSYNC.Call("disconnect_gdsync_owner_changed", node, callable);
	}
	#endregion


	// Lobby functions -------------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Lobby Functions

	/// <summary>
	/// Attempts to retrieve all publicly visible lobbies from the server.
	/// Will emit the signal <see cref="LobbiesReceived"/> once the server has collected all lobbies.
	/// </summary>
	public static void GetPublicLobbies()
	{
		GDSYNC.Call("get_public_lobbies");
	}

	/// <summary>
	/// Attempts to retrieve a publicly visible lobby from the server.
	/// Will emit the signal <see cref="LobbyReceived"/> once the server has collected the lobby information.
	/// </summary>
	/// <param name="lobbyName">The name of the lobby.</param>
	public static void GetPublicLobby(string lobbyName)
	{
		GDSYNC.Call("get_public_lobby", lobbyName);
	}

	/// <summary>
	/// Attempts to create a lobby on the server. If successful <see cref="LobbyCreated"/> is emitted.
	/// If it fails <see cref="LobbyCreationFailed"/> is emitted. Creating a lobby has a cooldown of 3 seconds.
	/// </summary>
	/// <param name="name">The name of the lobby you want to create. Has a maximum of 32 characters.</param>
	/// <param name="password">The password of the lobby. Leave empty if you want everyone to be able to join without a password.
	/// Has a maximum of 16 characters.</param>
	/// <param name="isPublic">If true, the lobby will be visible when using <see cref="GetPublicLobbies"/>.</param>
	/// <param name="playerLimit">The player limit of the lobby. If 0 it will automatically be set to the maximum your plan allows.
	/// This is also the case if the limit entered exceeds your plan limit.</param>
	/// <param name="tags">Any starting tags you would like to add to the lobby.</param>
	/// <param name="data">Any starting data you would like to add to the lobby.</param>
	public static void CreateLobby(string name, string password = "", bool isPublic = true, int playerLimit = 0, Dictionary tags = null, Dictionary data = null)
	{
		if (tags == null)
		{
			tags = new Dictionary();
		}

		if (data == null)
		{
			data = new Dictionary();
		}

		GDSYNC.Call("lobby_create", name, password, isPublic, playerLimit, tags, data);
	}

	/// <summary>
	/// Attempts to join an existing lobby. If successful <see cref="LobbyJoined"/> is emitted.
	/// If it fails <see cref="LobbyJoinFailed"/> is emitted.
	/// Using this function might cause your Client ID to change when joining a lobby that is not on your current server.
	/// </summary>
	/// <param name="name">The name of the lobby you are trying to join.</param>
	/// <param name="password">The password of the lobby you are trying to join.
	/// If the lobby has no password this can have any value.</param>
	public static void JoinLobby(string name, string password = "")
	{
		GDSYNC.Call("lobby_join", name, password);
	}

	/// <summary>
	/// Closes the lobby you are currently in, blocking any new players from joining. The lobby will still be visible when using <see cref="GetPublicLobbies"/>.
	/// </summary>
	public static void CloseLobby()
	{
		GDSYNC.Call("lobby_close");
	}

	/// <summary>
	/// Opens the lobby you are currently in, allowing new players to join.
	/// </summary>
	public static void OpenLobby()
	{
		GDSYNC.Call("lobby_open");
	}

	/// <summary>
	/// Sets the visibility of the lobby you are currently in. Decides whether the lobby shows up when using <see cref="GetPublicLobbies"/>.
	/// </summary>
	/// <param name="isPublic">If the lobby should be visible or not.</param>
	public static void SetLobbyVisibility(bool isPublic)
	{
		GDSYNC.Call("lobby_set_visibility", isPublic);
	}

	/// <summary>
	/// Changes the name of the current lobby. Only works for the host of the lobby. If successful <see cref="LobbyNameChanged"/> is emitted.
	/// If it fails <see cref="LobbyNameChangeFailed"/> is emitted. Changing the lobby name shares a 3 second cooldown with <see cref="CreateLobby(string, string, bool, int, Dictionary, Dictionary)"/>.
	/// </summary>
	/// <param name="name">The new lobby name. Has a maximum of 32 characters.</param>
	public static void ChangeLobbyName(string name)
	{
		GDSYNC.Call("lobby_change_name", name);
	}

	/// <summary>
	/// Changes the password of the lobby. Only works for the host of the lobby.
	/// </summary>
	/// <param name="password">The new password of the lobby.</param>
	public static void ChangeLobbyPassword(string password)
	{
		GDSYNC.Call("lobby_change_password", password);
	}

	/// <summary>
	/// Leaves the lobby you are currently in. This does not emit any signals.
	/// </summary>
	public static void LeaveLobby()
	{
		GDSYNC.Call("lobby_leave");
	}

	/// <summary>
	/// Kicks a client from the current lobby. Only works for the host of the lobby.
	/// </summary>
	/// <param name="clientId">The ID of the client you want to kick.</param>
	/// <param name="reason">An optional reason sent to the kicked client.</param>
	public static void KickLobbyClient(int clientId, string reason = "")
	{
		GDSYNC.Call("lobby_kick_client", clientId, reason);
	}

	/// <summary>
	/// Returns the client IDs of all clients in the current lobby.
	/// </summary>
	/// <returns>An array of client IDs in the current lobby.</returns>
	public static Array GetLobbyClients()
	{
		return (Array)GDSYNC.Call("lobby_get_all_clients");
	}

	/// <summary>
	/// Returns the client IDs of all clients in the current lobby.
	/// </summary>
	/// <returns>An array of client IDs in the current lobby.</returns>
	public static Array GetAllClients()
	{
		return GetLobbyClients();
	}

	/// <summary>
	/// Returns the amount of players in the current lobby.
	/// </summary>
	/// <returns>The number of players in the current lobby.</returns>
	public static int GetLobbyPlayerCount()
	{
		return (int)GDSYNC.Call("lobby_get_player_count");
	}

	/// <summary>
	/// Gets the current lobby name.
	/// </summary>
	/// <returns>The name of the current lobby.</returns>
	public static string GetLobbyName()
	{
		return (string)GDSYNC.Call("lobby_get_name");
	}

	/// <summary>
	/// Gets the current lobby visibility. Returns true if the lobby is publicly visible.
	/// </summary>
	/// <returns>True if the lobby is publicly visible, false otherwise.</returns>
	public static bool GetLobbyVisibility()
	{
		return (bool)GDSYNC.Call("lobby_get_visibility");
	}

	/// <summary>
	/// Returns the player limit of the current lobby.
	/// </summary>
	/// <returns>The maximum number of players allowed in the lobby.</returns>
	public static int GetLobbyPlayerLimit()
	{
		return (int)GDSYNC.Call("lobby_get_player_limit");
	}

	/// <summary>
	/// Returns true if the current lobby has a password.
	/// </summary>
	/// <returns>True if the lobby requires a password, false otherwise.</returns>
	public static bool LobbyHasPassword()
	{
		return (bool)GDSYNC.Call("lobby_has_password");
	}

	/// <summary>
	/// Adds a new or updates the value of a tag. Tags are publicly visible data that is returned with <see cref="GetPublicLobbies"/>.
	/// Especially useful when displaying information like the gamemode or map.
	/// <para>This does not instantly update, so it won't have an effect on <see cref="HasLobbyTag(string)"/> and <see cref="GetLobbyTag(string, Variant)"/> until
	/// a response from the server is returned. If the operation was successful <see cref="LobbyTagChanged"/> is emitted.</para>
	/// </summary>
	/// <param name="key">The key of the tag.</param>
	/// <param name="value">The value of the tag that should be stored.</param>
	public static void SetLobbyTag(string key, Variant value)
	{
		GDSYNC.Call("lobby_set_tag", key, value);
	}

	/// <summary>
	/// Deletes an existing tag.
	/// <para>This does not instantly update, so it won't have an effect on <see cref="HasLobbyTag(string)"/> and <see cref="GetLobbyTag(string, Variant)"/> until
	/// a response from the server is returned. If the operation was successful <see cref="LobbyTagChanged"/> is emitted.</para>
	/// </summary>
	/// <param name="key">The key of the tag.</param>
	public static void EraseLobbyTag(string key)
	{
		GDSYNC.Call("lobby_erase_tag", key);
	}

	/// <summary>
	/// Returns true if a tag with the given key exists.
	/// </summary>
	/// <param name="key">The key of the tag.</param>
	/// <returns>True if the tag exists, false otherwise.</returns>
	public static bool HasLobbyTag(string key)
	{
		return (bool)GDSYNC.Call("lobby_has_tag", key);
	}

	/// <summary>
	/// Gets the value of a lobby tag.
	/// </summary>
	/// <param name="key">The key of the tag.</param>
	/// <param name="defaultValue">The default value that is returned if the given key does not exist.</param>
	/// <returns>The value of the tag, or the default value if the tag doesn't exist.</returns>
	public static Variant GetLobbyTag(string key, Variant defaultValue = default)
	{
		return GDSYNC.Call("lobby_get_tag", key, defaultValue);
	}

	/// <summary>
	/// Returns a dictionary with all lobby tags and their values.
	/// </summary>
	/// <returns>A dictionary containing all lobby tags and their values.</returns>
	public static Dictionary GetAllLobbyTags()
	{
		return (Dictionary)GDSYNC.Call("lobby_get_all_tags");
	}

	/// <summary>
	/// Adds new or updates existing lobby data. Data is private data that can only be viewed from inside the lobby.
	/// <para>This does not instantly update, so it won't have an effect on <see cref="HasLobbyData(string)"/> and <see cref="GetLobbyData(string, Variant)"/> until
	/// a response from the server is returned. If operation was successful <see cref="LobbyDataChanged"/> is emitted.</para>
	/// </summary>
	/// <param name="key">The key of the data.</param>
	/// <param name="value">The value of the data that should be stored.</param>
	public static void SetLobbyData(string key, Variant value)
	{
		GDSYNC.Call("lobby_set_data", key, value);
	}

	/// <summary>
	/// Deletes existing data.
	/// <para>This does not instantly update, so it won't have an effect on <see cref="HasLobbyData(string)"/> and <see cref="GetLobbyData(string, Variant)"/> until
	/// a response from the server is returned. If operation was successful <see cref="LobbyDataChanged"/> is emitted.</para>
	/// </summary>
	/// <param name="key">The key of the data.</param>
	public static void EraseLobbyData(string key)
	{
		GDSYNC.Call("lobby_erase_data", key);
	}

	/// <summary>
	/// Returns true if data with the given key exists.
	/// </summary>
	/// <param name="key">The key of the data.</param>
	/// <returns>True if the data exists, false otherwise.</returns>
	public static bool HasLobbyData(string key)
	{
		return (bool)GDSYNC.Call("lobby_has_data", key);
	}

	/// <summary>
	/// Gets the value of lobby data.
	/// </summary>
	/// <param name="key">The key of the data.</param>
	/// <param name="defaultValue">The default value that is returned if the given key does not exist.</param>
	/// <returns>The value of the data, or the default value if the data doesn't exist.</returns>
	public static Variant GetLobbyData(string key, Variant defaultValue = default)
	{
		return GDSYNC.Call("lobby_get_data", key, defaultValue);
	}

	/// <summary>
	/// Returns a dictionary with all lobby data and their values.
	/// </summary>
	/// <returns>A dictionary containing all lobby data and their values.</returns>
	public static Dictionary GetAllLobbyData()
	{
		return (Dictionary)GDSYNC.Call("lobby_get_all_data");
	}
	#endregion

	// Matchmaking functions -------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Matchmaking Functions

	/// <summary>
	/// Starts matchmaking. Starting a new request automatically cancels the previous request.
	/// Matchmaking is not available in local multiplayer.
	/// <para>Use <see cref="MatchmakingRequest.SetMinPlayers"/> to create a lobby before it is full;
	/// later queued players can still join while that lobby stays open.</para>
	/// <para>See <see cref="MatchmakingRequest"/> for all configuration options.</para>
	/// <example>
	/// <code>
	/// GDSync.MatchmakingMatchFound += (lobbyName) => GD.Print("Found " + lobbyName);
	/// GDSync.MatchmakingFailed += (error) => GD.PushError(error);
	///
	/// var request = new MatchmakingRequest(4)
	///     .SetMinPlayers(2)
	///     .SetRequiredTags(new Dictionary { { "Mode", "Co-op" } })
	///     .SetTimeout(60f);
	/// GDSync.StartMatchmaking(request);
	/// </code>
	/// </example>
	/// </summary>
	/// <param name="request">The request describing what kind of match to look for.</param>
	public static void StartMatchmaking(MatchmakingRequest request)
	{
		GDSYNC.Call("matchmaking_start", request.Request);
	}

	/// <summary>
	/// Cancels the active matchmaking request. Emits <see cref="MatchmakingCancelled"/>.
	/// </summary>
	public static void CancelMatchmaking()
	{
		GDSYNC.Call("matchmaking_cancel");
	}

	/// <summary>
	/// Returns whether a matchmaking request is currently active.
	/// </summary>
	public static bool MatchmakingIsActive()
	{
		return (bool)GDSYNC.Call("matchmaking_is_active");
	}

	/// <summary>
	/// Returns the status of the active matchmaking request.
	/// </summary>
	/// <returns>The current status. See <see cref="MATCHMAKING_STATUS"/> for possible values.</returns>
	public static MATCHMAKING_STATUS GetMatchmakingStatus()
	{
		return (MATCHMAKING_STATUS)(int)GDSYNC.Call("matchmaking_get_status");
	}

	/// <summary>
	/// Returns additional information about the status of the active matchmaking request,
	/// such as the amount of queued players. Empty if no request is active.
	/// </summary>
	public static Dictionary GetMatchmakingStatusDetails()
	{
		return (Dictionary)GDSYNC.Call("matchmaking_get_status_details");
	}
	#endregion

	// Player functions ------------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Player Functions

	/// <summary>
	/// Sets data for your client. Player data has a maximum size of 2048 bytes, if this limit is exceeded
	/// a critical error is printed.
	/// Emits <see cref="PlayerDataChanged"/>. It may take up to 1 second for this signal to be emitted, as player
	/// data is synchronized every second if altered.
	/// </summary>
	/// <param name="key">The key of the player data.</param>
	/// <param name="value">The value of the player data.</param>
	public static void SetPlayerData(string key, Variant value)
	{
		GDSYNC.Call("player_set_data", key, value);
	}

	/// <summary>
	/// Erases data for your client.
	/// Emits <see cref="PlayerDataChanged"/> with null as the value.
	/// </summary>
	/// <param name="key">The key of the player data.</param>
	public static void ErasePlayerData(string key)
	{
		GDSYNC.Call("player_erase_data", key);
	}

	/// <summary>
	/// Gets data from a specific client. If you want to retrieve your own data you can input your own id.
	/// You can get your own id using <see cref="GetClientID"/>.
	/// </summary>
	/// <param name="clientId">The Client ID of which client you would like to get the data from.</param>
	/// <param name="key">The key of the player data.</param>
	/// <param name="defaultValue">The default value that is returned if the given key does not exist.</param>
	/// <returns>The player data value, or the default value if the key doesn't exist.</returns>
	public static Variant GetPlayerData(int clientId, string key, Variant defaultValue = default)
	{
		return GDSYNC.Call("player_get_data", clientId, key, defaultValue);
	}

	/// <summary>
	/// Gets all data from a specific client. If you want to retrieve your own data you can input your own id.
	/// You can get your own id using <see cref="GetClientID"/>.
	/// </summary>
	/// <param name="clientId">The Client ID of which client you would like to get the data from.</param>
	/// <returns>A dictionary containing all player data for the specified client.</returns>
	public static Dictionary GetAllPlayerData(int clientId)
	{
		return (Dictionary)GDSYNC.Call("player_get_all_data", clientId);
	}

	/// <summary>
	/// Sets the username of the player. If enabled in the configuration menu, usernames can be set to unique.
	/// When this setting is enabled there can be no duplicate usernames inside a lobby.
	/// Emits <see cref="PlayerDataChanged"/> with the key "Username".
	/// </summary>
	/// <param name="username">The username of this client.</param>
	public static void SetPlayerUsername(string username)
	{
		GDSYNC.Call("player_set_username", username);
	}

	/// <summary>
	/// Gets the username of the player with the given client ID. By default uses the ID of the local player.
	/// </summary>
	/// <param name="defaultValue">The default value to return if the username was not found.</param>
	/// <returns>The username of the player, or the default value if not found.</returns>
	public static string GetPlayerUsername(string defaultValue = "")
	{
		return (string)GDSYNC.Call("player_get_username", GetClientID(), defaultValue);
	}

	/// <summary>
	/// Gets the username of the player with the given client ID.
	/// </summary>
	/// <param name="clientId">The client ID to query.</param>
	/// <param name="defaultValue">The default value to return if the username was not found.</param>
	public static string GetPlayerUsername(int clientId, string defaultValue = "")
	{
		return (string)GDSYNC.Call("player_get_username", clientId, defaultValue);
	}
	#endregion

	// Accounts & Persistent Data Storage ------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Accounts & Persistent Data Storage

	/// <summary>
	/// Creates an account in the database linked to the API key.
	/// </summary>
	/// <param name="email">The email of the account. The email has to be unique.</param>
	/// <param name="username">The username of the account. The username has to be unique. The username has to be between 3 and 20 characters long.</param>
	/// <param name="password">The password of the account. The password has to be between 3 and 20 characters long.</param>
	/// <returns>The result of the request as ACCOUNT_CREATION_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_CREATION_RESPONSE_CODE> CreateAccount(string email, string username, string password)
	{
		var result = await CallAwaited("account_create", new Array { email, username, password });
		return (ACCOUNT_CREATION_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Deletes an existing account in the database linked to the API key.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <param name="password">The password of the account.</param>
	/// <returns>The result of the request as ACCOUNT_DELETION_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_DELETION_RESPONSE_CODE> DeleteAccount(string email, string password)
	{
		var result = await CallAwaited("account_delete", new Array { email, password });
		return (ACCOUNT_DELETION_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Can be used to verify the email of an account. Requires email verification to be enabled in the User Accounts
	/// settings. An email can be verified by inputting the verification code sent to the email address.
	/// Verifying the email will automatically log in the user.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <param name="code">The verification code that was sent to the email address.</param>
	/// <param name="validTime">The time in seconds how long the login session is valid.</param>
	/// <returns>The result of the request as ACCOUNT_VERIFICATION_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_VERIFICATION_RESPONSE_CODE> VerifyAccount(string email, string code, float validTime = 86400)
	{
		var result = await CallAwaited("account_verify", new Array { email, code, validTime });
		return (ACCOUNT_VERIFICATION_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Sends a new verification code to the email address. A new code can only be sent once the most recent
	/// code has expired. Requires email verification to be enabled in the User Account settings.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <param name="password">The password of the account.</param>
	/// <returns>The result of the request as RESEND_VERIFICATION_RESPONSE_CODE.</returns>
	public static async Task<RESEND_VERIFICATION_RESPONSE_CODE> ResendVerificationCode(string email, string password)
	{
		var result = await CallAwaited("account_resend_verification_code", new Array { email, password });
		return (RESEND_VERIFICATION_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Returns if the specified account has a verified email.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_IS_VERIFIED_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="username">The username of the account.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": true}</returns>
	public static async Task<Dictionary> IsVerified(string username = "")
	{
		var result = await CallAwaited("account_is_verified", new Array { username });
		return (Dictionary)result[0];
	}

	/// <summary>Returns whether this client is currently logged into a GD-Sync account.</summary>
	public static bool AccountIsLoggedIn()
	{
		return (bool)GDSYNC.Call("account_is_logged_in");
	}

	/// <summary>
	/// Attempt to login into an existing account.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_LOGIN_RESPONSE_CODE response code.
	/// If the user is banned, it will include the "Banned" key, which contains the unix timestamp when the ban will
	/// expire. If the ban is permanent, the value will be -1.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <param name="password">The password of the account.</param>
	/// <param name="validTime">The time in seconds how long the login session is valid.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "BanTime": 1719973379}</returns>
	public static async Task<Dictionary> Login(string email, string password, float validTime = 86400)
	{
		var result = await CallAwaited("account_login", new Array { email, password, validTime });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Attempt to login with a previous session. If that session has not yet expired it will login using
	/// and refresh the session time.
	/// </summary>
	/// <param name="validTime">The time in seconds how long the login session is valid.</param>
	/// <returns>The result of the request as LOGIN_RESPONSE_CODE.</returns>
	public static async Task<LOGIN_RESPONSE_CODE> LoginFromSession(float validTime = 86400)
	{
		var result = await CallAwaited("account_login_from_session", new Array { validTime });
		return (LOGIN_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Invalidates the current login session.
	/// </summary>
	/// <returns>The result of the request as LOGOUT_RESPONSE_CODE.</returns>
	public static async Task<LOGOUT_RESPONSE_CODE> Logout()
	{
		var result = await CallAwaited("account_logout", new Array());
		return (LOGOUT_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Changes the username of the currently logged in account.
	/// </summary>
	/// <param name="newUsername">The new username. The username has to be unique and between 3 and 20 characters long.</param>
	/// <returns>The result of the request as CHANGE_USERNAME_RESPONSE_CODE.</returns>
	public static async Task<CHANGE_USERNAME_RESPONSE_CODE> ChangeAccountUsername(string newUsername)
	{
		var result = await CallAwaited("account_change_username", new Array { newUsername });
		return (CHANGE_USERNAME_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Changes the password of an existing account.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <param name="password">The current password of the account.</param>
	/// <param name="newPassword">The new password of the account.</param>
	/// <returns>The result of the request as CHANGE_PASSWORD_RESPONSE_CODE.</returns>
	public static async Task<CHANGE_PASSWORD_RESPONSE_CODE> ChangeAccountPassword(string email, string password, string newPassword)
	{
		var result = await CallAwaited("account_change_password", new Array { email, password, newPassword });
		return (CHANGE_PASSWORD_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Requests a password reset code for the specified account. The reset code will be sent to the email address.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <returns>The result of the request as REQUEST_PASSWORD_RESET_RESPONSE_CODE.</returns>
	public static async Task<REQUEST_PASSWORD_RESET_RESPONSE_CODE> RequestPasswordReset(string email)
	{
		var result = await CallAwaited("account_request_password_reset", new Array { email });
		return (REQUEST_PASSWORD_RESET_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Attempt to use a password reset code. If the code is valid the password of the account will be changed.
	/// See <see cref="RequestPasswordReset(string)"/> for sending the password reset code.
	/// </summary>
	/// <param name="email">The email of the account.</param>
	/// <param name="resetCode">The password reset code.</param>
	/// <param name="newPassword">The new password for the account.</param>
	/// <returns>The result of the request as RESET_PASSWORD_RESPONSE_CODE.</returns>
	public static async Task<RESET_PASSWORD_RESPONSE_CODE> ResetPassword(string email, string resetCode, string newPassword)
	{
		var result = await CallAwaited("account_reset_password", new Array { email, resetCode, newPassword });
		return (RESET_PASSWORD_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Bans the current logged-in account.
	/// </summary>
	/// <param name="banDuration">The ban duration in days. Any amount above 1000 days results in a permanent ban.</param>
	/// <returns>The result of the request as ACCOUNT_BAN_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_BAN_RESPONSE_CODE> BanAccount(float banDuration)
	{
		var result = await CallAwaited("account_ban", new Array { banDuration });
		return (ACCOUNT_BAN_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Files a report against the specified account.
	/// </summary>
	/// <param name="usernameToReport">The username of the account you want to report.</param>
	/// <param name="report">The report message. Has a maximum limit of 3000 characters.</param>
	/// <returns>The result of the request as REPORT_USER_RESPONSE_CODE.</returns>
	public static async Task<REPORT_USER_RESPONSE_CODE> CreateReport(string usernameToReport, string report)
	{
		var result = await CallAwaited("account_create_report", new Array { usernameToReport, report });
		return (REPORT_USER_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Sends a friend request to another account.
	/// </summary>
	/// <param name="friend">The username of the account you want to send the friend request to.</param>
	/// <returns>The result of the request as ACCOUNT_SEND_FRIEND_REQUEST_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_SEND_FRIEND_REQUEST_RESPONSE_CODE> SendFriendRequest(string friend)
	{
		var result = await CallAwaited("account_send_friend_request", new Array { friend });
		return (ACCOUNT_SEND_FRIEND_REQUEST_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Accepts a friend request from another account.
	/// </summary>
	/// <param name="friend">The username of the account you want to accept the friend request from.</param>
	/// <returns>The result of the request as ACCOUNT_ACCEPT_FRIEND_REQUEST_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_ACCEPT_FRIEND_REQUEST_RESPONSE_CODE> AcceptFriendRequest(string friend)
	{
		var result = await CallAwaited("account_accept_friend_request", new Array { friend });
		return (ACCOUNT_ACCEPT_FRIEND_REQUEST_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Removes a friend. Also used to deny incoming friend requests.
	/// </summary>
	/// <param name="friend">The username of the friend you want to remove.</param>
	/// <returns>The result of the request as ACCOUNT_REMOVE_FRIEND_RESPONSE_CODE.</returns>
	public static async Task<ACCOUNT_REMOVE_FRIEND_RESPONSE_CODE> RemoveFriend(string friend)
	{
		var result = await CallAwaited("account_remove_friend", new Array { friend });
		return (ACCOUNT_REMOVE_FRIEND_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Gets the friend status between you and another account. Information besides the FriendStatus is only
	/// available if the friend request is accepted.
	/// If the lobby name is not empty, the player is in a lobby.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_GET_FRIEND_STATUS_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="friend">The username of the account you want the friend status of.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": {"FriendStatus": 2, "Lobby": {"Name": "Epic Lobby", "HasPassword": false}}}</returns>
	public static async Task<Dictionary> GetFriendStatus(string friend)
	{
		var result = await CallAwaited("account_get_friend_status", new Array { friend });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Returns an array of all friends with their status. Information besides the FriendStatus is only
	/// available if the friend request is accepted.
	/// If the lobby name is not empty, the player is in a lobby.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_GET_FRIENDS_RESPONSE_CODE response code.
	/// </summary>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": [{"Username": "Epic Username", "FriendStatus": 2, "Lobby": {"Name": "Epic Lobby", "HasPassword": true}}, ...]}</returns>
	public static async Task<Dictionary> GetFriends()
	{
		var result = await CallAwaited("account_get_friends", new Array());
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Invites a friend to the current lobby.
	/// </summary>
	public static async Task<ACCOUNT_INVITE_FRIEND_TO_LOBBY_RESPONSE_CODE> InviteFriendToLobby(string friend)
	{
		var result = await CallAwaited("account_invite_friend_to_lobby", new Array { friend });
		return (ACCOUNT_INVITE_FRIEND_TO_LOBBY_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Returns the current account's pending lobby invitations.
	/// </summary>
	public static async Task<Dictionary> GetLobbyInvitations()
	{
		var result = await CallAwaited("account_get_lobby_invitations", new Array());
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Store a dictionary/document of data on the currently logged-in account using GD-Sync cloud storage. The document
	/// will be stored on the specified location. If the collections specified in the path don't already
	/// exist, they are automatically created. Documents may also be nested in other documents.
	/// <para>Documents can be private or public. If externally visible, other players may retrieve and read
	/// the document contents. Setting externallyVisible to true will automatically make all parent
	/// collections/documents visible as well. Setting externallyVisible to false will automatically
	/// hide all nested collections and documents.</para>
	/// </summary>
	/// <param name="path">The path where the document should be stored. An example path could be "saves/save1".</param>
	/// <param name="document">The data that you want to store in the cloud.</param>
	/// <param name="externallyVisible">Decides if the document is public or private.</param>
	/// <returns>The result of the request as SET_PLAYER_DOCUMENT_RESPONSE_CODE.</returns>
	public static async Task<SET_PLAYER_DOCUMENT_RESPONSE_CODE> SetPlayerDocument(string path, Dictionary document, bool externallyVisible = false)
	{
		var result = await CallAwaited("account_document_set", new Array { path, document, externallyVisible });
		return (SET_PLAYER_DOCUMENT_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Documents can be private or public. If externally visible, other players may retrieve and read
	/// the document contents. Setting externallyVisible to true will automatically make all parent
	/// collections/documents visible as well. Setting externallyVisible to false will automatically
	/// hide all nested collections and documents.
	/// </summary>
	/// <param name="path">The path of the document or collection.</param>
	/// <param name="externallyVisible">Decides if the document is public or private.</param>
	/// <returns>The result of the request as SET_EXTERNAL_VISIBLE_RESPONSE_CODE.</returns>
	public static async Task<SET_EXTERNAL_VISIBLE_RESPONSE_CODE> SetDocumentExternalVisible(string path, bool externallyVisible = false)
	{
		var result = await CallAwaited("account_document_set_external_visible", new Array { path, externallyVisible });
		return (SET_EXTERNAL_VISIBLE_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Retrieve a dictionary/document of data from the currently logged-in account using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_GET_DOCUMENT_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": {&lt;document&gt;}}</returns>
	public static async Task<Dictionary> GetPlayerDocument(string path)
	{
		var result = await CallAwaited("account_get_document", new Array { path });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Check if a dictionary/document or collection exists on the currently logged-in account using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_HAS_DOCUMENT_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": true}</returns>
	public static async Task<Dictionary> HasPlayerDocument(string path)
	{
		var result = await CallAwaited("account_has_document", new Array { path });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Browse through a collection from the currently logged-in account using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_BROWSE_COLLECTION_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": [{"ExternallyVisible": true, "Name": "profile", "Path": "saves/profile", "Type": "Document"}, ...]}</returns>
	public static async Task<Dictionary> BrowsePlayerCollection(string path)
	{
		var result = await CallAwaited("account_browse_collection", new Array { path });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Delete a dictionary/document or collection from the currently logged-in account using GD-Sync cloud storage.
	/// </summary>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>The result of the request as DELETE_PLAYER_DOCUMENT_RESPONSE_CODE.</returns>
	public static async Task<DELETE_PLAYER_DOCUMENT_RESPONSE_CODE> DeletePlayerDocument(string path)
	{
		var result = await CallAwaited("account_delete_document", new Array { path });
		return (DELETE_PLAYER_DOCUMENT_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Retrieve a dictionary/document of data from another account using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_GET_DOCUMENT_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="externalUsername">The username of the account you want to perform the action on.</param>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": {&lt;document&gt;}}</returns>
	public static async Task<Dictionary> GetExternalPlayerDocument(string externalUsername, string path)
	{
		var result = await CallAwaited("account_get_external_document", new Array { externalUsername, path });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Check if a dictionary/document or collection exists on another account using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_HAS_DOCUMENT_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="externalUsername">The username of the account you want to perform the action on.</param>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": true}</returns>
	public static async Task<Dictionary> HasExternalPlayerDocument(string externalUsername, string path)
	{
		var result = await CallAwaited("account_has_external_document", new Array { externalUsername, path });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Browse through a collection from another account using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the ACCOUNT_BROWSE_COLLECTION_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="externalUsername">The username of the account you want to perform the action on.</param>
	/// <param name="path">The path of the document or collection.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": [{"ExternallyVisible": true, "Name": "profile", "Path": "saves/profile", "Type": "Document"}, ...]}</returns>
	public static async Task<Dictionary> BrowseExternalPlayerCollection(string externalUsername, string path)
	{
		var result = await CallAwaited("account_browse_external_collection", new Array { externalUsername, path });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Check if a leaderboard exists using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the LEADERBOARD_EXISTS_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="leaderboard">The name of the leaderboard.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": true}</returns>
	public static async Task<Dictionary> LeaderboardExists(string leaderboard)
	{
		var result = await CallAwaited("leaderboard_exists", new Array { leaderboard });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Retrieve a list of all leaderboards using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the LEADERBOARD_GET_ALL_RESPONSE_CODE response code.
	/// </summary>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": ["Leaderboard1", "Leaderboard2"]}</returns>
	public static async Task<Dictionary> GetLeaderboards()
	{
		var result = await CallAwaited("leaderboard_get_all", new Array());
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Browse a leaderboard and all submitted scores using GD-Sync cloud storage.
	/// Returns a Dictionary with the format seen below and the LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="leaderboard">The name of the leaderboard.</param>
	/// <param name="pageSize">The amount of scores returned. The maximum page size is 100.</param>
	/// <param name="page">The page you want to retrieve. The first page is page 1.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "FinalPage": 7, "Result": [{"Rank": 1, "Score": 828, "Username": "User1", "Data": {"CustomValue": 1}}, ...]}</returns>
	public static async Task<Dictionary> BrowseLeaderboard(string leaderboard, int pageSize, int page)
	{
		var result = await CallAwaited("leaderboard_browse_scores", new Array { leaderboard, pageSize, page });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Get the score and rank of an account for a specific leaderboard using GD-Sync cloud storage.
	/// If the user has no score submission on the leaderboard, Score will be 0 and Rank -1.
	/// Returns a Dictionary with the format seen below and the LEADERBOARD_GET_SCORE_RESPONSE_CODE response code.
	/// </summary>
	/// <param name="leaderboard">The name of the leaderboard.</param>
	/// <param name="username">The username to get the score for.</param>
	/// <returns>A Dictionary with the format: {"Code": 0, "Result": {"Score": 100, "Rank": 1, "Data": {"CustomValue": 1}}}</returns>
	public static async Task<Dictionary> GetLeaderboardScore(string leaderboard, string username)
	{
		var result = await CallAwaited("leaderboard_get_score", new Array { leaderboard, username });
		return (Dictionary)result[0];
	}

	/// <summary>
	/// Submits a score to a leaderboard for the currently logged-in account using GD-Sync cloud storage.
	/// If the user already has a score submission, it will be overwritten.
	/// </summary>
	/// <param name="leaderboard">The name of the leaderboard.</param>
	/// <param name="score">The score you want to submit.</param>
	/// <param name="data">Any extra information you would like to attach to the score. This dictionary can be a maximum of 2048 bytes in size.</param>
	/// <returns>The result of the request as SUBMIT_SCORE_RESPONSE_CODE.</returns>
	public static async Task<SUBMIT_SCORE_RESPONSE_CODE> SubmitScore(string leaderboard, int score, Dictionary data = null)
	{
		var result = await CallAwaited("leaderboard_submit_score", new Array { leaderboard, score, data ?? new Dictionary() });
		return (SUBMIT_SCORE_RESPONSE_CODE)(int)result[0];
	}

	/// <summary>
	/// Deletes a score from a leaderboard for the currently logged-in account using GD-Sync cloud storage.
	/// </summary>
	/// <param name="leaderboard">The name of the leaderboard.</param>
	/// <returns>The result of the request as DELETE_SCORE_RESPONSE_CODE.</returns>
	public static async Task<DELETE_SCORE_RESPONSE_CODE> DeleteScore(string leaderboard)
	{
		var result = await CallAwaited("leaderboard_delete_score", new Array { leaderboard });
		return (DELETE_SCORE_RESPONSE_CODE)(int)result[0];
	}

	#endregion



	#region enums
	public enum CRITICAL_ERROR
	{
		LOBBY_DATA_FULL,
		LOBBY_TAGS_FULL,
		PLAYER_DATA_FULL,
		REQUEST_TOO_LARGE,
		OBJECT_IN_REQUEST,
	}

	public enum CONNECTION_FAILED
	{
		INVALID_PUBLIC_KEY,
		TIMEOUT,
		LOCAL_PORT_ERROR,
	}

	public enum LOBBY_CREATION_ERROR
	{
		LOBBY_ALREADY_EXISTS,
		NAME_TOO_SHORT,
		NAME_TOO_LONG,
		PASSWORD_TOO_LONG,
		TAGS_TOO_LARGE,
		DATA_TOO_LARGE,
		ON_COOLDOWN,
		LOCAL_PORT_ERROR,
	}

	public enum LOBBY_JOIN_ERROR
	{
		LOBBY_DOES_NOT_EXIST,
		LOBBY_IS_CLOSED,
		LOBBY_IS_FULL,
		INCORRECT_PASSWORD,
		DUPLICATE_USERNAME,
	}

	public enum LOBBY_NAME_CHANGE_ERROR
	{
		NAME_ALREADY_EXISTS,
		NAME_TOO_SHORT,
		NAME_TOO_LONG,
		ON_COOLDOWN,
	}

	public enum MATCHMAKING_SEARCH_MODE
	{
		PUBLIC_ONLY,
		PUBLIC_THEN_MATCHMAKE,
		MATCHMAKE_ONLY,
	}

	public enum MATCHMAKING_STATUS
	{
		INACTIVE,
		SEARCHING_PUBLIC,
		WAITING_FOR_PLAYERS,
		MATCH_FOUND,
		JOINING,
	}

	public enum MATCHMAKING_ERROR
	{
		INVALID_REQUEST,
		ALREADY_IN_LOBBY,
		NO_MATCH,
		TIMEOUT,
		UNSUPPORTED_LOCAL,
		JOIN_FAILED,
	}

	public enum LOBBY_SWITCH_ERROR
	{
		INVALID_RESERVATION,
		RESERVATION_EXPIRED,
		DESTINATION_UNREACHABLE,
		JOIN_FAILED,
		ROLLBACK_FAILED,
	}

	public enum EXPOSE_PERMISSION
	{
		ANYONE,
		HOST,
		CLIENT,
	}

	public enum NODE_REPLICATION_SETTINGS
	{
		INSTANTIATOR,
		SYNC_STARTING_CHANGES,
		EXCLUDED_PROPERTIES,
		SCENE,
		TARGET,
		ORIGINAL_PROPERTIES,
	}

	public enum NODE_REPLICATION_DATA
	{
		ID,
		CHANGED_PROPERTIES,
	}

	public enum ACCOUNT_CREATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		STORAGE_FULL,
		INVALID_EMAIL,
		INVALID_USERNAME,
		EMAIL_ALREADY_EXISTS,
		USERNAME_ALREADY_EXISTS,
		USERNAME_TOO_SHORT,
		USERNAME_TOO_LONG,
		PASSWORD_TOO_SHORT,
		PASSWORD_TOO_LONG,
	}

	public enum ACCOUNT_DELETION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_PASSWORD_INCORRECT,
	}

	public enum RESEND_VERIFICATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		VERIFICATION_DISABLED,
		ON_COOLDOWN,
		ALREADY_VERIFIED,
		EMAIL_OR_PASSWORD_INCORRECT,
		BANNED,
	}

	public enum ACCOUNT_VERIFICATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		INCORRECT_CODE,
		CODE_EXPIRED,
		ALREADY_VERIFIED,
		BANNED,
	}

	public enum IS_VERIFIED_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		USER_DOESNT_EXIST,
	}

	public enum LOGIN_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_PASSWORD_INCORRECT,
		NOT_VERIFIED,
		EXPIRED_SESSION,
		BANNED,
	}

	public enum LOGOUT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	public enum CHANGE_PASSWORD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		ON_COOLDOWN,
		EMAIL_OR_PASSWORD_INCORRECT,
		NOT_VERIFIED,
		BANNED,
	}

	public enum CHANGE_USERNAME_RESPONSE_CODE
	{

		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		ON_COOLDOWN,
		USERNAME_ALREADY_EXISTS,
		USERNAME_TOO_SHORT,
		USERNAME_TOO_LONG,
		INVALID_USERNAME
	}

	public enum RESET_PASSWORD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_CODE_INCORRECT,
		CODE_EXPIRED,
	}

	public enum REQUEST_PASSWORD_RESET_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		ON_COOLDOWN,
		EMAIL_DOESNT_EXIST,
		BANNED,
	}

	public enum SET_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
	}

	public enum GET_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	public enum BROWSE_PLAYER_COLLECTION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	public enum SET_EXTERNAL_VISIBLE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}


	public enum HAS_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	public enum DELETE_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	public enum REPORT_USER_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		REPORT_TOO_LONG,
		TOO_MANY_REPORTS,
		USER_DOESNT_EXIST,
	}

	public enum SUBMIT_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		LEADERBOARD_DOESNT_EXIST,
		DATA_TOO_LAGE,
	}

	public enum DELETE_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST
	}

	public enum GET_LEADERBOARDS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN
	}

	public enum HAS_LEADERBOARD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN
	}

	public enum BROWSE_LEADERBOARD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST
	}

	public enum GET_LEADERBOARD_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST,
		USER_DOESNT_EXIST
	}

	public enum ACCOUNT_SEND_FRIEND_REQUEST_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		USER_DOESNT_EXIST,
		FRIEND_ALREADY_ADDED,
		FRIENDS_LIST_FULL,
	}

	public enum ACCOUNT_ACCEPT_FRIEND_REQUEST_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		FRIEND_NOT_FOUND,
	}

	public enum ACCOUNT_REMOVE_FRIEND_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		FRIEND_DOESNT_EXIST,
	}

	public enum ACCOUNT_GET_FRIENDS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	public enum ACCOUNT_GET_FRIEND_STATUS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		USER_DOESNT_EXIST,
	}

	public enum ACCOUNT_INVITE_FRIEND_TO_LOBBY_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		USER_DOESNT_EXIST,
		NOT_FRIEND,
		NOT_IN_LOBBY,
	}

	public enum ACCOUNT_GET_LOBBY_INVITATIONS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	public enum FRIEND_STATUS
	{
		NONE,
		INCOMING_REQUEST,
		FRIEND,
		WAITING_FOR_REPLY,
	}

	public enum ACCOUNT_BAN_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
	}

	public enum LINK_STEAM_ACCOUNT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		ALREADY_LINKED,
		STEAM_ERROR,
	}

	public enum UNLINK_STEAM_ACCOUNT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STEAM_ERROR,
	}

	public enum STEAM_LOGIN_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		STEAM_ERROR,
		NOT_LINKED,
		NOT_VERIFIED,
		BANNED,
	}
	#endregion
}

/// <summary>
/// Builder for a matchmaking search passed to <see cref="GDSync.StartMatchmaking"/>.
/// <para>Construct a request, optionally chain configuration methods, then start matchmaking and handle
/// <see cref="GDSync.MatchmakingStarted"/>, <see cref="GDSync.MatchmakingStatusChanged"/>,
/// <see cref="GDSync.MatchmakingMatchFound"/>, <see cref="GDSync.MatchmakingFailed"/> and
/// <see cref="GDSync.MatchmakingCancelled"/>. Starting a new request cancels any active one.
/// Closed lobbies are never joined.</para>
/// <para>The constructor player limit is the maximum lobby size. <see cref="SetMinPlayers"/> controls how many
/// queued players are required before a match lobby is created (default: equal to the player limit).
/// After creation, more matching players can join while the lobby stays open.</para>
/// <example>
/// <code>
/// var request = new MatchmakingRequest(8)
///     .SetMinPlayers(2)
///     .SetRequiredTags(new Dictionary { { "Mode", "PvP" } })
///     .SetTimeout(60f);
/// GDSync.StartMatchmaking(request);
/// </code>
/// </example>
/// </summary>
public class MatchmakingRequest
{
	private const string SCRIPT_PATH = "res://addons/GD-Sync/Scripts/Types/MatchmakingRequest.gd";

	private static GDScript _script;

	/// <summary>
	/// The GDScript request this class configures. Used internally by <see cref="GDSync.StartMatchmaking"/>.
	/// </summary>
	internal GodotObject Request { get; }

	/// <summary>
	/// Creates a request whose lobbies hold up to <paramref name="playerLimit"/> players.
	/// <para>Until <see cref="SetMinPlayers"/> is called, the minimum to create a lobby equals
	/// <paramref name="playerLimit"/>. Must be greater than 0 and within your plan limit.</para>
	/// </summary>
	/// <param name="playerLimit">The maximum amount of players in lobbies created by this request.</param>
	public MatchmakingRequest(int playerLimit)
	{
		if (_script == null)
		{
			_script = GD.Load<GDScript>(SCRIPT_PATH);
		}

		Request = (GodotObject)_script.New(playerLimit);
	}

	/// <summary>
	/// Sets all required tags at once, matching the tags of <see cref="GDSync.CreateLobby"/>.
	/// <para>Public lobbies and queued players must include every entry. Replaces any previously set tags.
	/// Pass an empty dictionary to clear.</para>
	/// </summary>
	/// <param name="tags">The tags a lobby or queued player must have.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetRequiredTags(Dictionary tags)
	{
		Request.Call("set_required_tags", tags ?? new Dictionary());
		return this;
	}

	/// <summary>
	/// Sets whether to search public lobbies, the matchmaking queue, or both.
	/// Defaults to <see cref="GDSync.MATCHMAKING_SEARCH_MODE.PUBLIC_THEN_MATCHMAKE"/>.
	/// </summary>
	/// <param name="mode">Where this request may find players.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetSearchMode(GDSync.MATCHMAKING_SEARCH_MODE mode)
	{
		Request.Call("set_search_mode", (int)mode);
		return this;
	}

	/// <summary>
	/// Sets how many queued players are required before a match lobby is created.
	/// <para>Lobby capacity remains the constructor player limit. For example, a limit of 8 with a minimum of 2
	/// creates a lobby at two players; others may join until the lobby is full or closed. Must be between 1 and
	/// the player limit. Defaults to the full player limit.</para>
	/// </summary>
	/// <param name="minPlayers">The amount of players required to create a lobby.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetMinPlayers(int minPlayers)
	{
		Request.Call("set_min_players", minPlayers);
		return this;
	}

	/// <summary>
	/// Sets how long to wait before failing with <see cref="GDSync.MATCHMAKING_ERROR.TIMEOUT"/>.
	/// Use 0 to wait indefinitely.
	/// </summary>
	/// <param name="seconds">The amount of seconds before the request times out.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetTimeout(float seconds)
	{
		Request.Call("set_timeout", seconds);
		return this;
	}

	/// <summary>
	/// Enables skill based matching using this player's rating.
	/// <para>If never called, skill is ignored. Use together with <see cref="SetSkillRange"/>.</para>
	/// </summary>
	/// <param name="rating">The skill rating of this player.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetSkillRating(float rating)
	{
		Request.Call("set_skill_rating", rating);
		return this;
	}

	/// <summary>
	/// Configures the allowed skill distance from <see cref="SetSkillRating"/>.
	/// <para>The allowed range starts at <paramref name="initial"/> and may grow toward <paramref name="maximum"/>
	/// by <paramref name="expansionPerSecond"/> while waiting. Expansion is applied when candidates are evaluated.</para>
	/// </summary>
	/// <param name="initial">The starting allowed skill distance.</param>
	/// <param name="maximum">The maximum allowed skill distance.</param>
	/// <param name="expansionPerSecond">How much the allowed distance grows per second of waiting.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetSkillRange(float initial, float maximum, float expansionPerSecond = 0f)
	{
		Request.Call("set_skill_range", initial, maximum, expansionPerSecond);
		return this;
	}

	/// <summary>
	/// Disables skill matching so only tags, limits and search mode apply.
	/// </summary>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest ClearSkillMatching()
	{
		Request.Call("clear_skill_matching");
		return this;
	}

	/// <summary>
	/// Sets private lobby data at once, matching the data of <see cref="GDSync.CreateLobby"/>.
	/// <para>Applied only to lobbies created by matchmaking, not when joining existing public lobbies.
	/// Replaces any previously set data. Pass an empty dictionary to clear.</para>
	/// </summary>
	/// <param name="data">The starting data of lobbies created by this request.</param>
	/// <returns>This request, so calls can be chained.</returns>
	public MatchmakingRequest SetLobbyData(Dictionary data)
	{
		Request.Call("set_lobby_data", data ?? new Dictionary());
		return this;
	}
}
