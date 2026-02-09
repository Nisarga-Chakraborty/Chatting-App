import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  late RtcEngine agoraEngine;
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isLoading = true;

  final String appId = "abc397b17b114396ba339e6f8fb0e585";
  final String channelName = "studenthub_channel";
  final String token =
      "007eJxTYChhmWzrL3bIofVVTpiljxav172IzDcT59fcnjZJtGfhq6UKDIlJycaW5kmGQGRoYmxplpRobGyZapZmkZZkkGpqYXrQuSOzIZCRYbtwHgsjAwSC+EIMxSWlKal5JRmlSfHJGYl5eak5DAwA2QYkYg==";

  @override
  void initState() {
    super.initState();
    initAgora();
  }

  Future<void> initAgora() async {
    try {
      // Request permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        Permission.camera,
      ].request();

      // Check if permissions are granted
      if (statuses[Permission.microphone] != PermissionStatus.granted ||
          statuses[Permission.camera] != PermissionStatus.granted) {
        debugPrint("Permissions not granted");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Camera/Microphone permission required"),
            ),
          );
        }
        return;
      }

      // Create the engine
      agoraEngine = createAgoraRtcEngine();
      await agoraEngine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Enable video
      await agoraEngine.enableVideo();
      await agoraEngine.startPreview();

      // Set event handlers
      agoraEngine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint("✅ Local user joined: ${connection.localUid}");
            setState(() {
              _localUserJoined = true;
              _isLoading = false;
            });
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint("✅ Remote user joined: $remoteUid");
            setState(() {
              _remoteUid = remoteUid;
            });
          },
          onUserOffline:
              (
                RtcConnection connection,
                int remoteUid,
                UserOfflineReasonType reason,
              ) {
                debugPrint(
                  "❌ Remote user offline: $remoteUid, reason: $reason",
                );
                setState(() {
                  _remoteUid = null;
                });
              },
          onError: (ErrorCodeType err, String msg) {
            debugPrint("❌ Agora Error: $err - $msg");
          },
          onConnectionStateChanged:
              (
                RtcConnection connection,
                ConnectionStateType state,
                ConnectionChangedReasonType reason,
              ) {
                debugPrint("🔄 Connection state: $state, reason: $reason");
              },
          onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
            debugPrint("⚠️ Token will expire soon");
          },
          onRequestToken: (RtcConnection connection) {
            debugPrint("⚠️ Token expired, need new token");
          },
        ),
      );

      // Join channel with proper media options
      await agoraEngine.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          // Enable publishing
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          // Enable subscribing
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );

      debugPrint("📞 Attempting to join channel: $channelName");
    } catch (e) {
      debugPrint("❌ Error initializing Agora: $e");
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  void dispose() {
    agoraEngine.leaveChannel();
    agoraEngine.release();
    super.dispose();
  }

  Widget _renderLocalVideo() {
    if (_localUserJoined) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: agoraEngine,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    } else {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
  }

  Widget _renderRemoteVideo() {
    if (_remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: agoraEngine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: channelName),
        ),
      );
    } else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 80, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              "Waiting for remote user...",
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("StudentHub Video Call"),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Joining call..."),
                ],
              ),
            )
          : Stack(
              children: [
                // Black background
                Container(color: Colors.black),
                // Remote video (full screen)
                Center(child: _renderRemoteVideo()),
                // Local video (small preview)
                Positioned(
                  top: 40,
                  right: 20,
                  child: Container(
                    width: 120,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _renderLocalVideo(),
                    ),
                  ),
                ),
                // Connection status indicator
                if (_localUserJoined)
                  Positioned(
                    top: 40,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _remoteUid != null
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _remoteUid != null ? "Connected" : "Waiting",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await agoraEngine.leaveChannel();
          if (mounted) Navigator.pop(context);
        },
        backgroundColor: Colors.red,
        child: const Icon(Icons.call_end, color: Colors.white),
      ),
    );
  }
}
