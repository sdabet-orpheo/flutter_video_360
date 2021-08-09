import Flutter
import UIKit
import AVKit

public class Video360View: UIView, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {}
    var channel: FlutterMethodChannel!

    private var timer: Timer?
    private var player: AVPlayer!
    private var swifty360View: Swifty360View!

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func initFlutter(
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        flutterRegistrar registrar: FlutterPluginRegistrar
    ) {

        let viewName = String(format: "kino_video_360_%lld", viewId)
        self.channel = FlutterMethodChannel(name: viewName,
                                            binaryMessenger: registrar.messenger())


        registrar.addMethodCallDelegate(self, channel: self.channel)
        registrar.addApplicationDelegate(self)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            guard let argMaps = call.arguments as? Dictionary<String, Any>,
                  let url = argMaps["url"] as? String,
                  let isAutoPlay = argMaps["isAutoPlay"] as? Bool,
                  let isRepeat = argMaps["isRepeat"] as? Bool,
                  let width = argMaps["width"] as? Double,
                  let height = argMaps["height"] as? Double else {
                result(FlutterError(code: call.method, message: "Missing argument", details: nil))
                return
            }
            self.initView(url: url, width: width, height: height)

            if isAutoPlay {
                self.checkPlayerState()
            }

            if isRepeat {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(self.playerFinish(noti:)),
                                                       name: .AVPlayerItemDidPlayToEndTime,
                                                       object: nil)
            }

            self.updateTime()
        case "dispose":
            // TODO : dispose func implemention

        case "play":
            self.play()

        case "stop":
            self.stop()

        case "reset":
            self.reset()

        case "jumpTo":
            guard let argMaps = call.arguments as? Dictionary<String, Any>,
                  let time = argMaps["millisecond"] as? Double else {
                result(FlutterError(code: call.method, message: "Missing argument", details: nil))
                return
            }
            self.jumpTo(second: time / 1000.0)

        case "seekTo":
            guard let argMaps = call.arguments as? Dictionary<String, Any>,
                  let time = argMaps["millisecond"] as? Double else {
                result(FlutterError(code: call.method, message: "Missing argument", details: nil))
                return
            }
            self.seekTo(second: time / 1000.0)

        case "onPanUpdate":
            guard let argMaps = call.arguments as? Dictionary<String, Any>,
                  let isStart = argMaps["isStart"] as? Bool,
                  let x = argMaps["x"] as? Double,
                  (0 ... Double(self.swifty360View.frame.maxX)) ~= x,
                  let y = argMaps["y"] as? Double,
                  (0 ... Double(self.swifty360View.frame.maxY)) ~= y else {
                result(FlutterError(code: call.method, message: "Missing argument", details: nil))
                return
            }
            let point = CGPoint(x: x, y: y)
            self.swifty360View.cameraController.handlePan(isStart: isStart, point: point)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}


// MARK: - Interface
extension Video360View {

    private func initView(url: String, width: Double, height: Double) {
        guard let videoURL = URL(string: url) else { return }
        self.player = AVPlayer(url: videoURL)

        let motionManager = Swifty360MotionManager.shared

        self.swifty360View = Swifty360View(withFrame: CGRect(x: 0.0, y: 0.0, width: width, height: height),
                                           player: self.player,
                                           motionManager: motionManager)
        self.swifty360View.setup(player: self.player, motionManager: motionManager)
        self.addSubview(self.swifty360View)
    }

    // repeat
    @objc private func playerFinish(noti: NSNotification) {
        self.reset()
    }

    // play
    private func play() {
        self.swifty360View.player.play()
    }

    // stop
    private func stop() {
        self.swifty360View.player.pause()
    }

    // reset
    private func reset() {
        self.jumpTo(second: .zero)
    }

    // jumpTo
    private func jumpTo(second: Double) {
        let sec = CMTimeMakeWithSeconds(Float64(second), preferredTimescale: Int32(NSEC_PER_SEC))
        self.swifty360View.player.seek(to: sec)
        self.checkPlayerState()
    }

    // seekTo
    private func seekTo(second: Double) {
        let current = self.swifty360View.player.currentTime()
        let sec = CMTimeMakeWithSeconds(Float64(second), preferredTimescale: Int32(NSEC_PER_SEC))
        self.swifty360View.player.seek(to: current + sec)
        self.checkPlayerState()
    }

    // updateTime
    private func updateTime() {
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        self.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            let duration = Int(CMTimeGetSeconds(time))
            let durationSeconds = duration % 60
            let durationMinutes = duration / 60
            let durationString = String(format: "%02d:%02d", durationMinutes, durationSeconds)

            let totalDuration = self.player.currentItem?.duration
            let totalCMTime = CMTimeGetSeconds(totalDuration ?? CMTimeMake(value: 0, timescale: 1))
            if totalCMTime.isNaN {
                return
            }
            let total = Int(totalCMTime)
            let totalSeconds = total % 60
            let totalMinutes = total / 60
            let totalString = String(format: "%02d:%02d", totalMinutes, totalSeconds)

            self.channel.invokeMethod("updateTIme", arguments: ["duration": durationString, "total": totalString])
        }
    }
}


extension Video360View {
    // check player state - for auto play
    private func checkPlayerState() {
        self.timer = Timer(timeInterval: 0.5,
                           target: self,
                           selector: #selector(self.check),
                           userInfo: nil,
                           repeats: true)
        RunLoop.main.add(self.timer!, forMode: .common)
    }

    @objc private func check() {
        guard let currentItem = self.player.currentItem,
              currentItem.status == AVPlayerItem.Status.readyToPlay,
              currentItem.isPlaybackLikelyToKeepUp,
              !self.player.isPlaying else { return }

        self.swifty360View.play()

        self.timer?.invalidate()
        self.timer = nil
    }
}


// MARK: - AVPlayer Extension
extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}
