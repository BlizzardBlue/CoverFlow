//
//  ViewController.swift
//  CoverFlow
//
//  Created by Thatcher Clough on 10/18/20.
//

import UIKit
import MediaPlayer
import ColorThiefSwift
import StoreKit
import Reachability
import AVFoundation
import Keys

class ViewController: UITableViewController, UITextFieldDelegate {
    
    // MARK: Cells, slider, and variables
    
    let keys = CoverFlowKeys()
    var countryCode: String!
    
    @IBOutlet var bridgeCell: UITableViewCell!
    @IBOutlet var lightsCell: UITableViewCell!
    @IBOutlet var startButtonText: UILabel!
    
    var currentHues: [NSNumber] = []
    var currentLightsStates: [String: PHSLightState] = [:]
    static var bridge: PHSBridge! = nil
    static var bridgeInfo: BridgeInfo! = nil
    static var authenticated: Bool = false
    static var lights: [String]! = []
    
    var colorDuration: Double = 0.0
    @IBOutlet var colorDurationLabel: UILabel!
    @IBOutlet var colorDurationSlider: UISlider!
    @IBAction func colorDurationChanged(_ sender: UISlider?) {
        let rounded: Int = Int(colorDurationSlider.value)
        colorDurationSlider.value = Float(rounded)
        
        colorDuration = Double(rounded) * 0.25
        colorDurationLabel.text = "\(colorDuration) sec"
        DispatchQueue.global(qos: .background).async {
            UserDefaults.standard.setValue(rounded, forKey: "colorDuration")
        }
    }
    
    var transitionDuration: Double = 0.0
    @IBOutlet var transitionDurationLabel: UILabel!
    @IBOutlet var transitionDurationSlider: UISlider!
    @IBAction func transitionDurationChanged(_ sender: UISlider?) {
        let rounded: Int = Int(transitionDurationSlider.value)
        transitionDurationSlider.value = Float(rounded)
        
        transitionDuration = Double(rounded) * 0.25
        transitionDurationLabel.text = "\(transitionDuration) sec"
        DispatchQueue.global(qos: .background).async {
            UserDefaults.standard.setValue(rounded, forKey: "transitionDuration")
        }
    }
    
    var brightness: Double = 0.0
    @IBOutlet var brightnessLabel: UILabel!
    @IBOutlet var brightnessSlider: UISlider!
    @IBAction func brightnessChanged(_ sender: UISlider?) {
        let rounded: Int = Int(brightnessSlider.value)
        brightnessSlider.value = Float(rounded)
        
        brightness = Double(rounded) * 2.54
        brightnessLabel.text = "\(rounded)%"
        DispatchQueue.global(qos: .background).async {
            UserDefaults.standard.setValue(rounded, forKey: "brightness")
        }
    }
    
    // MARK: View Related

    override func viewDidLoad() {
        super.viewDidLoad()
        
        getCountryCode()
        
        observeReachability()
        
        colorDurationSlider.minimumValue = 0
        colorDurationSlider.maximumValue = 40
        colorDurationSlider.tintAdjustmentMode = .normal
        transitionDurationSlider.minimumValue = 0
        transitionDurationSlider.maximumValue = 20
        transitionDurationSlider.tintAdjustmentMode = .normal
        brightnessSlider.minimumValue = 0
        brightnessSlider.maximumValue = 100
        brightnessSlider.tintAdjustmentMode = .normal
        
        let defaults = UserDefaults.standard
        let colorTimeDefaults = defaults.value(forKey: "colorDuration")
        if colorTimeDefaults == nil {
            defaults.setValue(4.0, forKey: "colorDuration")
            colorDurationSlider.value = 4.0
        } else {
            colorDurationSlider.value = colorTimeDefaults as! Float
        }
        let transitionTimeDefaults = defaults.value(forKey: "transitionDuration")
        if transitionTimeDefaults == nil {
            defaults.setValue(8.0, forKey: "transitionDuration")
            transitionDurationSlider.value = 8.0
        } else {
            transitionDurationSlider.value = transitionTimeDefaults as! Float
        }
        let brightnessDefaults = defaults.value(forKey: "brightness")
        if brightnessDefaults == nil {
            defaults.setValue(100, forKey: "brightness")
            brightnessSlider.value = 100
        } else {
            brightnessSlider.value = brightnessDefaults as! Float
        }
        
        colorDurationChanged(nil)
        transitionDurationChanged(nil)
        brightnessChanged(nil)
        
        setUpLastConnectedBridge()
    }
    
    func getCountryCode() {
        DispatchQueue.global(qos: .background).async {
            let controller = SKCloudServiceController()
            controller.requestStorefrontCountryCode { countryCode, error in
                if error != nil {
                    self.countryCode = "us"
                } else {
                    self.countryCode = countryCode
                }
            }
        }
    }
    
    func setUpLastConnectedBridge() {
        var lastConnectedBridge: BridgeInfo! {
            get {
                if let lastConnectedBridge = PHSKnownBridge.lastConnectedBridge {
                    let lastConnectedBridgeInfo = BridgeInfo(ipAddress: lastConnectedBridge.ipAddress, uniqueId: lastConnectedBridge.uniqueId)
                    return lastConnectedBridgeInfo
                } else {
                    return nil
                }
            }
        }
        
        if lastConnectedBridge != nil {
            ViewController.bridgeInfo = lastConnectedBridge
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        checkPermissions()
        
        if ViewController.bridgeInfo != nil && (!ViewController.authenticated || (ViewController.authenticated && ViewController.bridge.bridgeConfiguration.networkConfiguration.ipAddress != ViewController.bridgeInfo.ipAddress)) {
            connectFromBridgeInfo()
        }
        
        if ViewController.lights.isEmpty {
            lightsCell.detailTextLabel?.text = "None selected"
        } else {
            lightsCell.detailTextLabel?.text = "\(ViewController.lights.count) selected"
        }
        
        self.tableView.reloadData()
    }
    
    func connectFromBridgeInfo() {
        ViewController.bridge = buildBridge(info: ViewController.bridgeInfo)
        ViewController.bridge.connect()
        DispatchQueue.main.async {
            if self.presentingViewController != nil {
                self.dismiss(animated: true, completion: nil)
            }
            let connectionAlert = UIAlertController(title: "Connecting to bridge...", message: nil, preferredStyle: UIAlertController.Style.alert)
            self.present(connectionAlert, animated: true, completion: nil)
        }
    }
    
    var hasPermissions: Bool = false
    var canPushNotifications: Bool = false
    func checkPermissions() {
        MPMediaLibrary.requestAuthorization { authorizationStatus in
            if authorizationStatus == .authorized {
                let _ = ProcessInfo.processInfo.hostName
                self.hasPermissions = true
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
                    granted, error in
                    self.canPushNotifications = granted
                }
            } else {
                self.alert(title: "Notice", body: "CoverFlow will not work on this device because Apple Music access is not enabled. Please enable \"Media and Apple Music\" access in settings.")
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        startButtonText.text = "Start"
        
        stopBackgrounding()
        
        if timer != nil {
            timer.invalidate()
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        checkPermissions()
        
        if hasPermissions {
            if identifier == "toLightSelection" && !ViewController.authenticated {
                alert(title: "Error", body: "Please connect to a bridge before continuing.")
                return false
            } else {
                return true
            }
        } else {
            return false
        }
    }
    
    // MARK: Table Related
    
    var canStartOrStop: Bool = true
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)!
        cell.setSelected(false, animated: true)
        
        if indexPath.section == 2 && indexPath.row == 0 {
            checkPermissions()
            
            if hasPermissions{
                if !ViewController.authenticated {
                    alert(title: "Error", body: "Please connect to a bridge before continuing.")
                } else {
                    if canStartOrStop {
                        canStartOrStop = false
                        if startButtonText.text == "Start" {
                            startButtonText.text = "Starting..."
                            
                            DispatchQueue.global(qos: .background).async {
                                self.startBackgrounding()
                                
                                self.getCurrentLightsStates()
                                
                                self.start()
                            }
                        } else {
                            startButtonText.text = "Start"
                            
                            DispatchQueue.global(qos: .background).async {
                                self.stopBackgrounding()
                                
                                self.setCurrentLightsStates()
                                
                                if self.timer != nil {
                                    self.timer.invalidate()
                                }
                                
                                self.canStartOrStop = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: Bridge related
    
    func buildBridge(info: BridgeInfo) -> PHSBridge {
        return PHSBridge.init(block: { (builder) in
            builder?.connectionTypes = .local
            builder?.ipAddress = info.ipAddress
            builder?.bridgeID  = info.uniqueId
            
            builder?.bridgeConnectionObserver = self
            builder?.add(self)
        }, withAppName: "CoverFlow", withDeviceName: "iDevice")
    }
    
    func getCurrentLightsStates() {
        currentLightsStates.removeAll()
        
        for light in ViewController.bridge.bridgeState.getDevicesOf(.light) {
            let lightName = (light as! PHSDevice).name!
            
            if ViewController.lights.contains(lightName) {
                currentLightsStates[lightName] = (light as! PHSLightPoint).lightState
            }
        }
    }
    
    func setCurrentLightsStates() {
        for light in ViewController.bridge.bridgeState.getDevicesOf(.light) {
            let lightName = (light as! PHSDevice).name!
            
            if ViewController.lights.contains(lightName) && currentLightsStates.keys.contains(lightName) {
                let lightPoint = light as! PHSLightPoint
                
                lightPoint.update(currentLightsStates[lightName], allowedConnectionTypes: .local) { (responses, errors, returnCode) in
                    if errors != nil && errors!.count > 0 {
                        var errorText = "Could not restore light state."
                        for generalError in errors! {
                            if let error = generalError as? PHSClipError {
                                errorText += " " + error.errorDescription + "."
                            }
                        }
                        self.alertAndNotify(title: "Error", body: errorText)
                    }
                }
            }
        }
    }
    
    var timer: Timer!
    func start() {
        var currentHueIndex: Int = 0
        var albumAndArtist = getCurrentAlbumAndArtist()
        let wait = self.colorDuration + self.transitionDuration
        
        getCoverImageAndSetCurrentSongHues()
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: true) { (timer) in
                if wait != (self.colorDuration + self.transitionDuration) {
                    timer.invalidate()
                    self.start()
                }
                
                if !self.currentHues.isEmpty {
                    for light in ViewController.bridge.bridgeState.getDevicesOf(.light) {
                        if ViewController.lights.contains((light as! PHSDevice).name) {
                            if let lightPoint: PHSLightPoint = light as? PHSLightPoint {
                                let lightState = PHSLightState()
                                if self.brightness == 0 {
                                    lightState.on = false
                                } else {
                                    lightState.on = true
                                    lightState.hue = self.currentHues[currentHueIndex]
                                    lightState.saturation = 254
                                    lightState.brightness = NSNumber(value: self.brightness)
                                    lightState.transitionTime = NSNumber(value: self.transitionDuration * 10)
                                }
                                lightPoint.update(lightState, allowedConnectionTypes: .local) { (responses, errors, returnCode) in
                                    if errors != nil && errors!.count > 0 {
                                        var errorText = "Could not set light state."
                                        for generalError in errors! {
                                            if let error = generalError as? PHSClipError {
                                                errorText += " " + error.errorDescription + "."
                                            }
                                        }
                                        self.alertAndNotify(title: "Error", body: errorText)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if self.backgroundPlayer != nil && !self.backgroundPlayer!.isPlaying {
                    self.startBackgrounding()
                }
                
                let currentAlbumAndArtist = self.getCurrentAlbumAndArtist()
                if currentAlbumAndArtist != albumAndArtist {
                    albumAndArtist = currentAlbumAndArtist
                    self.getCoverImageAndSetCurrentSongHues()
                    currentHueIndex = 0
                    
                    self.playAudio(fileName: "songChange", fileExtension: "mp3")
                } else {
                    currentHueIndex += 1
                    if currentHueIndex >= self.currentHues.count {
                        currentHueIndex = 0
                    }
                }
            }
            RunLoop.current.add(self.timer, forMode: .default)
            
            if self.startButtonText.text == "Starting..." {
                self.startButtonText.text = "Stop"
                self.canStartOrStop = true
            }
        }
    }
    
    func getCurrentAlbumAndArtist() -> String {
        let player = MPMusicPlayerController.systemMusicPlayer
        let nowPlaying: MPMediaItem? = player.nowPlayingItem
        let albumName = nowPlaying?.albumTitle
        let artistName = nowPlaying?.artist
        
        if albumName == nil || artistName == nil {
            return "N/A"
        } else {
            return albumName! + artistName!
        }
    }
    
    func getCoverImageAndSetCurrentSongHues() {
        currentHues.removeAll()
        
        let player = MPMusicPlayerController.systemMusicPlayer
        let nowPlaying: MPMediaItem? = player.nowPlayingItem
        let albumArt = nowPlaying?.artwork
        let albumName = nowPlaying?.albumTitle
        let artistName = (nowPlaying?.albumArtist != nil) ? nowPlaying?.albumArtist : nowPlaying?.artist
        
        if nowPlaying != nil {
            let image = albumArt?.image(at: CGSize(width: 200, height: 200)) ?? nil
            
            if image != nil {
                setCurrentSongHues(image: image!)
            } else {
                if albumName != nil && artistName != nil {
                    self.getCoverFromAPI(albumName: albumName!, artistName: artistName!) { (url) in
                        if url != nil {
                            self.getData(from: URL(string: url!)!) { data, response, error in
                                if data == nil || error != nil {
                                    self.alertAndNotify(title: "Error", body: "Could not downlaod the current song's album cover.")
                                    return
                                }
                                
                                DispatchQueue.main.async() {
                                    let image = UIImage(data: data!)
                                    self.setCurrentSongHues(image: image!)
                                }
                            }
                        } else {
                            self.alertAndNotify(title: "Error", body: "Could not get the current song's album cover. The Apple Music API did not return a URL.")
                        }
                    }
                } else {
                    alertAndNotify(title: "Error", body: "Could not get the current song's album cover. Album name or artist is nil.")
                }
            }
        } else {
            alertAndNotify(title: "Error", body: "Could not get the current song's album cover. Now playing item is nil.")
        }
    }
    
    func getData(from url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
        URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
    }
    
    func getCoverFromAPI(albumName: String, artistName: String, completion: @escaping (String?)->()) {
        let searchTerm  = albumName.replacingOccurrences(of: " ", with: "+")
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(countryCode ?? "us")/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: searchTerm),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "types", value: "albums"),
        ]
        let url = components.url!
        
        let session = URLSession.shared
        var request = URLRequest(url: url)
        request.setValue("Bearer \(keys.appleMusicAPIKey1)", forHTTPHeaderField: "Authorization")
        
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
            guard error == nil else {
                return
            }
            guard let data = data else {
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    if let results = json["results"] as? [String: Any] {
                        if let albums = results["albums"] as? [String: Any] {
                            if let data = albums["data"] as? NSArray {
                                for album in data {
                                    guard let albumJson = album as? [String: Any] else {
                                        continue
                                    }
                                    guard let attributes = albumJson["attributes"] as? [String: Any] else {
                                        continue
                                    }
                                    
                                    if (attributes["name"] as! String == albumName) && (attributes["artistName"] as! String == artistName) {
                                        guard let artwork = attributes["artwork"] as? [String: Any] else {
                                            continue
                                        }
                                        
                                        var url = artwork["url"] as? String
                                        url = url?.replacingOccurrences(of: "{w}", with: "200")
                                        url = url?.replacingOccurrences(of: "{h}", with: "200")
                                        return completion(url)
                                    }
                                }
                                return completion(nil)
                            }
                        }
                    }
                }
            } catch {
                return
            }
        })
        task.resume()
    }
    
    func setCurrentSongHues(image: UIImage) {
        guard let colors = ColorThief.getPalette(from: image, colorCount: 4, quality: 5, ignoreWhite: true) else {
            self.alertAndNotify(title: "Notice", body: "Could not extract colors form the current song's album cover.")
            return
        }
        
        for color in colors {
            let rgb = rgbToHue(r: CGFloat(color.r), g: CGFloat(color.g), b: CGFloat(color.b))
            let hue: CGFloat = rgb.h
            let saturation: CGFloat = rgb.s
            if hue > 0 && saturation > 0.2 {
                currentHues.append((hue * 182) as NSNumber)
            }
        }
        
        if currentHues.isEmpty {
            alertAndNotify(title: "Notice", body: "The current song's album cover does not have any distinct colors.")
        }
    }
    
    func rgbToHue(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let minV: CGFloat = CGFloat(min(r, g, b))
        let maxV: CGFloat = CGFloat(max(r, g, b))
        let delta: CGFloat = maxV - minV
        var hue: CGFloat = 0
        if delta != 0 {
            if r == maxV {
                hue = (g - b) / delta
            } else if g == maxV {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue *= 60
            if hue < 0 {
                hue += 360
            }
        }
        let saturation = maxV == 0 ? 0 : (delta / maxV)
        let brightness = maxV
        return (h: hue, s: saturation, b: brightness)
    }
    
    // MARK: Other
    
    var audioPlayer: AVAudioPlayer?
    func playAudio(fileName: String, fileExtension: String) {
        do {
            let audioFile = URL(fileURLWithPath: Bundle.main.path(forResource: fileName, ofType: fileExtension)!)
            audioPlayer = try AVAudioPlayer(contentsOf: audioFile)
            audioPlayer!.volume = 0.05
            audioPlayer!.prepareToPlay()
            audioPlayer!.play()
        } catch {
            alert(title: "Notice", body: "Could not play sound \"\(fileName).\(fileExtension)\".")
        }
    }
    
    var backgroundPlayer: AVAudioPlayer?
    func startBackgrounding() {
        do {
            let audioCheck = URL(fileURLWithPath: Bundle.main.path(forResource: "audioCheck", ofType: "mp3")!)
            backgroundPlayer = try AVAudioPlayer(contentsOf: audioCheck)
            backgroundPlayer!.numberOfLoops = -1
            backgroundPlayer!.prepareToPlay()
            backgroundPlayer!.play()
        } catch {
            alert(title: "Notice", body: "Could not initialize background mode.")
        }
        
        var backgroundTask = UIBackgroundTaskIdentifier(rawValue: 0)
        backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        })
    }
    
    func stopBackgrounding() {
        if backgroundPlayer != nil && backgroundPlayer!.isPlaying {
            backgroundPlayer?.stop()
        }
    }
    
    func alertAndNotify(title: String, body: String) {
        alert(title: title, body: body)
        if canPushNotifications {
            pushNotification(title: title, body: body)
        }
    }
    
    func alert(title: String, body: String) {
        DispatchQueue.main.async {
            if self.presentingViewController == nil {
                let alert = UIAlertController(title: title, message: body, preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    func pushNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    private var reachability : Reachability!
    func observeReachability(){
        do {
            self.reachability = try Reachability()
            NotificationCenter.default.addObserver(self, selector:#selector(self.reachabilityChanged), name: NSNotification.Name.reachabilityChanged, object: nil)
            try self.reachability.startNotifier()
        }
        catch {
            print("could not initiate connection manager")
        }
    }
    
    var firstDetection: Bool = true
    @objc func reachabilityChanged(note: Notification) {
        if firstDetection {
            firstDetection = false
        } else {
            let reachability = note.object as! Reachability
            let connection = reachability.connection
            
            if connection == .cellular || connection == .unavailable || connection == .unavailable {
                if ViewController.bridge != nil {
                    ViewController.bridge.disconnect()
                    
                    stopBackgrounding()
                    
                    if timer != nil {
                        timer.invalidate()
                    }
                }
            } else if connection == .wifi {
                setUpLastConnectedBridge()
                connectFromBridgeInfo()
            }
        }
    }
}

extension ViewController: PHSBridgeConnectionObserver {
    func bridgeConnection(_ bridgeConnection: PHSBridgeConnection!, handle connectionEvent: PHSBridgeConnectionEvent) {
        switch connectionEvent {
        case .couldNotConnect:
            print("could not connect")
            
            if self.presentedViewController as? UIAlertController != nil {
                self.dismiss(animated: true, completion: nil)
            }
            alert(title: "Error", body: "Could not connect to the bridge.")
            
            ViewController.bridge = nil
            ViewController.bridgeInfo = nil
            ViewController.authenticated = false
            break
        case .connected:
            print("connected")
            break
        case .connectionLost:
            print("connection lost")
            
            alertAndNotify(title: "Notice", body: "Lost connection to the bridge.")
            break
        case .connectionRestored:
            print("connection restored")
            
            alertAndNotify(title: "Notice", body: "Restored connection to the bridge.")
            break
        case .disconnected:
            print("disconnected")
            
            bridgeCell.detailTextLabel?.text = "Not connected"
            lightsCell.detailTextLabel?.text = "None selected"
            ViewController.lights.removeAll()
            startButtonText.text = "Start"
            
            ViewController.bridgeInfo = nil
            ViewController.bridge = nil
            ViewController.authenticated = false
            
            tableView.reloadData()
            
            if bridgeCell.detailTextLabel?.text == "Connected" {
                alert(title: "Notice", body: "Disconnected from the bridge.")
            }
            break
        case .notAuthenticated:
            print("not authenticated")
            
            ViewController.authenticated = false
            break
        case .linkButtonNotPressed:
            print("button not pressed")
            
            if self.presentedViewController as? UIAlertController != nil {
                self.dismiss(animated: true, completion: nil)
            }
            if self.presentedViewController == nil {
                let pushButton = self.storyboard?.instantiateViewController(withIdentifier: "PushButtonViewController") as! PushButtonViewController
                pushButton.isModalInPresentation = true
                self.present(pushButton, animated: true, completion: nil)
            }
            break
        case .authenticated:
            print("authenticated")
            
            if self.presentedViewController as? UIAlertController != nil {
                self.dismiss(animated: true, completion: nil)
            }
            ViewController.authenticated = true
            
            bridgeCell.detailTextLabel?.text = "Connected"
            
            let defaults = UserDefaults.standard
            let lights = defaults.value(forKey: "lights")
            if  lights == nil {
                defaults.setValue([], forKey: "lights")
            } else {
                ViewController.lights = defaults.value(forKey: "lights") as? [String]
            }
            
            if ViewController.lights.isEmpty {
                lightsCell.detailTextLabel?.text = "None selected"
            } else {
                lightsCell.detailTextLabel?.text = "\(ViewController.lights.count) selected"
            }
            
            self.tableView.reloadData()
            break
        default:
            return
        }
    }
    
    func bridgeConnection(_ bridgeConnection: PHSBridgeConnection!, handleErrors connectionErrors: [PHSError]!) {}
}

extension ViewController: PHSBridgeStateUpdateObserver {
    func bridge(_ bridge: PHSBridge!, handle updateEvent: PHSBridgeStateUpdatedEvent) {
        switch updateEvent {
        case .bridgeConfig:
            print("bridge config")
            break
        case .fullConfig:
            print("full congif")
            break
        case .initialized:
            print("good")
            break
        default:
            return
        }
    }
}

extension PHSKnownBridge {
    class var lastConnectedBridge: PHSKnownBridge? {
        get {
            let knownBridges: [PHSKnownBridge] = PHSKnownBridges.getAll()
            let sortedKnownBridges: [PHSKnownBridge] = knownBridges.sorted { (bridge1, bridge2) -> Bool in
                return bridge1.lastConnected < bridge2.lastConnected
            }
            return sortedKnownBridges.first
        }
    }
}
