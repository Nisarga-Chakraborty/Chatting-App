import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late RtcEngine agoraEngine;
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isLoading = true;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  Timer? _callTimer;
  int _callDuration = 0;

  final String appId = "YOUR_APP_ID";
  final String channelName = "studenthub_voice_channel";
  final String token = "YOUR_TOKEN";

  @override
  void initState() {
    super.initState();
    initAgora();
  }

  Future<void> initAgora() async {
    try {
      // Request microphone permission
      PermissionStatus status = await Permission.microphone.request();

      if (status != PermissionStatus.granted) {
        debugPrint("❌ Microphone permission not granted");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Microphone permission required")),
          );
          Navigator.pop(context);
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

      // Disable video for voice-only call
      await agoraEngine.disableVideo();

      // Enable audio
      await agoraEngine.enableAudio();

      // Set audio profile for voice call
      await agoraEngine.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Enable speaker by default
      await agoraEngine.setEnableSpeakerphone(_isSpeakerOn);

      // Set event handlers
      agoraEngine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint("✅ Local user joined: ${connection.localUid}");
            setState(() {
              _localUserJoined = true;
              _isLoading = false;
            });
            _startCallTimer();
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

      // Join channel
      await agoraEngine.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );

      debugPrint("📞 Attempting to join voice channel: $channelName");
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

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });
    await agoraEngine.muteLocalAudioStream(_isMuted);
    debugPrint(_isMuted ? "🔇 Muted" : "🔊 Unmuted");
  }

  Future<void> _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    await agoraEngine.setEnableSpeakerphone(_isSpeakerOn);
    debugPrint(_isSpeakerOn ? "🔊 Speaker ON" : "📱 Speaker OFF");
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    await agoraEngine.leaveChannel();
    await agoraEngine.release();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    agoraEngine.leaveChannel();
    agoraEngine.release();
    super.dispose();
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 2),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text("Voice Call"),
        backgroundColor: const Color(0xFF16213e),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    "Connecting...",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                const Spacer(),
                // User Avatar with Pulse Animation
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulse effect
                    if (_remoteUid != null)
                      Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                      ),
                    // Main avatar
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _remoteUid != null
                              ? [Colors.green.shade400, Colors.green.shade700]
                              : [
                                  Colors.orange.shade400,
                                  Colors.orange.shade700,
                                ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_remoteUid != null
                                        ? Colors.green
                                        : Colors.orange)
                                    .withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 70,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                // User Status
                Text(
                  _remoteUid != null ? "Connected" : "Waiting for user...",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // Call Duration
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatDuration(_callDuration),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const Spacer(),
                // Connection Status Indicator
                if (_localUserJoined)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _remoteUid != null
                          ? Colors.green.withOpacity(0.15)
                          : Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: _remoteUid != null
                            ? Colors.green.withOpacity(0.4)
                            : Colors.orange.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _remoteUid != null
                                ? Colors.green
                                : Colors.orange,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (_remoteUid != null
                                            ? Colors.green
                                            : Colors.orange)
                                        .withOpacity(0.6),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _remoteUid != null
                              ? "Call in progress"
                              : "Waiting to connect",
                          style: TextStyle(
                            color: _remoteUid != null
                                ? Colors.green.shade300
                                : Colors.orange.shade300,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // Control Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute Button
                      _buildControlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: _isMuted ? "Unmute" : "Mute",
                        color: _isMuted ? Colors.red : Colors.white,
                        backgroundColor: _isMuted
                            ? Colors.red.withOpacity(0.2)
                            : Colors.white.withOpacity(0.15),
                        onTap: _toggleMute,
                      ),
                      // End Call Button
                      _buildControlButton(
                        icon: Icons.call_end,
                        label: "End Call",
                        color: Colors.white,
                        backgroundColor: Colors.red,
                        onTap: _endCall,
                      ),
                      // Speaker Button
                      _buildControlButton(
                        icon: _isSpeakerOn
                            ? Icons.volume_up
                            : Icons.phone_in_talk,
                        label: _isSpeakerOn ? "Speaker" : "Earpiece",
                        color: _isSpeakerOn ? Colors.blue : Colors.white,
                        backgroundColor: _isSpeakerOn
                            ? Colors.blue.withOpacity(0.2)
                            : Colors.white.withOpacity(0.15),
                        onTap: _toggleSpeaker,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
    );
  }
}
