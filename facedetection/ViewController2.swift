//
//  ViewController2.swift
//  facedetection
//
//  Created by Axiom5 on 7/28/18.
//  Copyright © 2018 Axiom5. All rights reserved.
//

import UIKit
import AVFoundation
import FirebaseMLVision
class ViewController2: UIViewController , AVCaptureVideoDataOutputSampleBufferDelegate {
    var status="Text"
    private lazy var vision=Vision.vision()
    private lazy var onDeviceTextDetector=vision.textDetector()
    @IBOutlet weak var cameraView: UIView!
    override func viewDidLoad() {
        super.viewDidLoad()
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        cameraView.layer.addSublayer(previewLayer)
        setUpAnnotationOverlayView()
        setUpCaptureSessionOutput()
        setUpCaptureSessionInput()

        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        var alert=UIAlertController(title: "Text Detection Mode ON", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil) )
        self.present(alert, animated: true, completion: nil)
        startSession()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        stopSession()
    }
 
    private var previewLayer: AVCaptureVideoPreviewLayer!
    override func viewDidLayoutSubviews() {
        
        previewLayer.frame=cameraView.frame
    }
    private lazy var sessionQueue = DispatchQueue(label: Constants.sessionQueueLabel)
    private lazy var captureSession = AVCaptureSession()
    
    private var isUsingFrontCamera = false
    private lazy var annotationOverlayView: UIView = {
        precondition(isViewLoaded)
        let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return annotationOverlayView
    }()
    
    
    
    private func setUpAnnotationOverlayView() {
        cameraView.addSubview(annotationOverlayView)
        NSLayoutConstraint.activate([
            annotationOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            annotationOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            annotationOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            annotationOverlayView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),
            ])
    }
    private func startSession() {
        sessionQueue.async {
            self.captureSession.startRunning()
        }
    }
    
    private func stopSession() {
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
    }
    private func setUpCaptureSessionOutput() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = AVCaptureSession.Preset.medium
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings =
                [(kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA]
            let outputQueue = DispatchQueue(label: Constants.videoDataOutputQueueLabel)
            output.setSampleBufferDelegate(self, queue: outputQueue)
            guard self.captureSession.canAddOutput(output) else {
                print("Failed to add capture session output.")
                return
            }
            self.captureSession.addOutput(output)
            self.captureSession.commitConfiguration()
        }
    }
    private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices.first { $0.position == position }
    }
    private func setUpCaptureSessionInput() {
        sessionQueue.async {
            let cameraPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
            guard let device = self.captureDevice(forPosition: cameraPosition) else {
                print("Failed to get capture device for camera position: \(cameraPosition)")
                return
            }
            do {
                let currentInputs = self.captureSession.inputs
                for input in currentInputs {
                    self.captureSession.removeInput(input)
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else {
                    print("Failed to add capture session input.")
                    return
                }
                self.captureSession.addInput(input)
            } catch {
                print("Failed to create capture device input: \(error.localizedDescription)")
            }
        }
    }
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
        ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        let visionImage = VisionImage(buffer: sampleBuffer)
        let metadata = VisionImageMetadata()
        let orientation = UIUtilities.imageOrientation(
            fromDevicePosition: isUsingFrontCamera ? .front : .back
        )
        let visionOrientation = UIUtilities.visionImageOrientation(from: orientation)
        metadata.orientation = visionOrientation
        visionImage.metadata = metadata
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        
        switch status{
        case "Text":
            
             detectTextOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
        default:
            
            detectFacesOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
        }
       
            //detectFacesOnDevice(in: visionImage, width: imageWidth, height: imageHeight)
        
    }
    private func detectFacesOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
        let options = VisionFaceDetectorOptions()
        options.landmarkType = .all
        options.classificationType = .all
        options.isTrackingEnabled = true
        let faceDetector = vision.faceDetector(options: options)
        faceDetector.detect(in: image) { features, error in
            guard error == nil, let features = features, !features.isEmpty else {
                self.removeDetectionAnnotations()
                print("On-Device face detector returned no results.")
                return
            }
            self.removeDetectionAnnotations()
            for face in features  {
                let frame=face.frame
                
                let normalizedRect = CGRect(
                    x: face.frame.origin.x / width,
                    y: face.frame.origin.y / height,
                    width: face.frame.size.width / width,
                    height: face.frame.size.height / height
                )
                
                
                var message=""
                let standardizedRect =
                    self.previewLayer.layerRectConverted(fromMetadataOutputRect: normalizedRect).standardized
                UIUtilities.addRectangle(
                    standardizedRect,
                    to: self.annotationOverlayView,
                    color: UIColor.green
                )
                
                
                if face.hasHeadEulerAngleY {
                    let rotY = face.headEulerAngleY  // Head is rotated to the right rotY degrees
                    message+="Head is rotated to the right \(rotY) Y degrees \n"
                }
                if face.hasHeadEulerAngleZ {
                    let rotZ = face.headEulerAngleZ  // Head is rotated upward rotZ degrees
                      message+="Head is rotated to the right \(rotZ) Z degrees\n"
                }
                
                // If landmark detection was enabled (mouth, ears, eyes, cheeks, and
                // nose available):
                if let leftEye = face.landmark(ofType: .leftEye) {
                    let leftEyePosition = leftEye.position
                    message+="Position of left eye: \(leftEyePosition)\n"
                }
                
                // If classification was enabled:
                if face.hasSmilingProbability {
                    let smileProb = face.smilingProbability
                    if face.smilingProbability>0.4{
                          message+="Person is smiling\n"
                    }
               
                }
                
                if face.hasRightEyeOpenProbability {
                    let rightEyeOpenProb = face.rightEyeOpenProbability
                    if rightEyeOpenProb > 0.4{
                        message+="Right eye is open\n"

                    }
                }
                
                if face.hasLeftEyeOpenProbability {
                    let rightEyeOpenProb = face.leftEyeOpenProbability
                    if rightEyeOpenProb > 0.4{
                        message+="Left eye is open"
                        
                    }
                }
                // If face tracking was enabled:
                if face.hasTrackingID {
                    let trackingId = face.trackingID
                }
                var alert=UIAlertController(title: "Face Features Detected", message:message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil) )
                self.present(alert, animated: true, completion: nil)
            }
            
            
        }
    }
    private func detectTextOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
        onDeviceTextDetector.detect(in: image) { features, error in
            guard error == nil, let features = features, !features.isEmpty else {
                self.removeDetectionAnnotations()
                print("On-Device text detector returned no results.")
                return
            }
            self.removeDetectionAnnotations()
            for feature in features {
                guard feature is VisionTextBlock, let block = feature as? VisionTextBlock else { continue }
                let points = self.convertedPoints(from: block.cornerPoints, width: width, height: height)
                UIUtilities.addShape(
                    withPoints: points,
                    to: self.annotationOverlayView,
                    color: UIColor.purple
                )
                
                for line in block.lines {
                    let points = self.convertedPoints(from: line.cornerPoints, width: width, height: height)
                    UIUtilities.addShape(
                        withPoints: points,
                        to: self.annotationOverlayView,
                        color: UIColor.orange
                    )
                    
                    for element in line.elements {
                        let normalizedRect = CGRect(
                            x: element.frame.origin.x / width,
                            y: element.frame.origin.y / height,
                            width: element.frame.size.width / width,
                            height: element.frame.size.height / height
                        )
                        let convertedRect = self.previewLayer.layerRectConverted(
                            fromMetadataOutputRect: normalizedRect
                        )
                        UIUtilities.addRectangle(
                            convertedRect,
                            to: self.annotationOverlayView,
                            color: UIColor.green
                        )
                        let label = UILabel(frame: convertedRect)
                        label.text = element.text
                        label.adjustsFontSizeToFitWidth = true
                        self.annotationOverlayView.addSubview(label)
                    }
                }
            }
        }
    }
    private func removeDetectionAnnotations() {
        for annotationView in annotationOverlayView.subviews {
            annotationView.removeFromSuperview()
        }
    }
    private func convertedPoints(
        from points: [NSValue],
        width: CGFloat,
        height: CGFloat
        ) -> [NSValue] {
        return points.map {
            let cgPointValue = $0.cgPointValue
            let normalizedPoint = CGPoint(x: cgPointValue.x / width, y: cgPointValue.y / height)
            let cgPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
            let value = NSValue(cgPoint: cgPoint)
            return value
        }
    }
    @IBAction func DetectText(_ sender: UIBarButtonItem)
    {
        self.status="Text"
        var alert=UIAlertController(title: "Text Detection Mode ON", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil) )
        
        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func DetectFace(_ sender: UIBarButtonItem)
    {
          self.status="Face"
        var alert=UIAlertController(title: "Face Detection Mode ON", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil) )
        self.present(alert, animated: true, completion: nil)
      
    }
    
    
}
private enum Constants {
    static let alertControllerTitle = "Vision Detectors"
    static let alertControllerMessage = "Select a detector"
    static let cancelActionTitleText = "Cancel"
    static let videoDataOutputQueueLabel = "com.google.firebaseml.visiondetector.VideoDataOutputQueue"
    static let sessionQueueLabel = "com.google.firebaseml.visiondetector.SessionQueue"
}



    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */


