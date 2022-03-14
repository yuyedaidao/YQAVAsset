//
//  AVAssetExtension.swift
//  Pods
//
//  Created by 王叶庆 on 2022/3/12.
//

import Foundation
import AVFoundation
import SwiftEgg

extension AVAsset {
    
    fileprivate func videoComposition(_ videoInfo: AVAsset.VideoInfo) -> AVVideoComposition? {
        // 需要旋转方向
        let videoTrack = self.tracks(withMediaType: .video).first!
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        var transform: CGAffineTransform = CGAffineTransform.identity
        switch videoInfo.orientation {
        case .r90:
            let size = CGSize(width: videoInfo.size.height, height: videoInfo.size.width)
            videoComposition.renderSize = size
            composition.naturalSize = size
            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0)
        case .r180:
            videoComposition.renderSize = videoInfo.size
            composition.naturalSize = videoInfo.size
            transform = CGAffineTransform(translationX: videoInfo.size.width, y: videoInfo.size.height).rotated(by: CGFloat.pi)
        case .r270:
            let size = CGSize(width: videoInfo.size.height, height: videoInfo.size.width)
            videoComposition.renderSize = size
            composition.naturalSize = size
            transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.height)
        case .r0:
            videoComposition.renderSize = videoInfo.size
            composition.naturalSize = videoInfo.size
        }
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let timeRange = CMTimeRange(start: .zero, duration: self.duration)
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        do {
            try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch let error {
            print(error)
            return nil
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        return videoComposition
    }
    
    /// 视频转码
    /// - Parameters:
    ///   - presetName: presetName
    ///   - tempDirectory: 临时文件目录
    ///   - completion: completion
    ///   - tryIfNeed:  如果presetName不符合要求的话，会从符合的里选择最后一个重新导出
    ///   - returnOriginalDataIfFailed: 如果tryIfNeed为false，还无法导出的话就返回原始数据
    public func compressVideo(presetName: String = AVAssetExportPresetHighestQuality, tempDirectory: URL? = nil, completion: @escaping (Result<URL, Error>) -> (), tryIfNeed: Bool = true, returnOriginalDataIfFailed: Bool = true) {
        let tempDirectory = tempDirectory ?? FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))\(arc4random()).mp4")
        AVAssetExportSession.determineCompatibility(ofExportPreset: presetName, with: self, outputFileType: .mp4) { allow in
            guard allow else {
                completion(.failure(Egg(492, message: "无法导出视频")))
                return
            }
            guard let exportSession = AVAssetExportSession(asset: self, presetName: presetName) else {
                completion(.failure(Egg("AVAssetExportSession获取失败")))
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            
            if let videoInfo = self.videoInfo, let composition = self.videoComposition(videoInfo) {
                exportSession.videoComposition = composition
            }
            exportSession.exportAsynchronously {[weak self] () in
                guard let self = self else {return}
                switch exportSession.status {
                case .completed:
                    completion(.success(outputURL))
                case .failed:
                    if tryIfNeed {
                        guard let lastPreset = AVAssetExportSession.exportPresets(compatibleWith: self).last else {
                            completion(.failure(exportSession.error ?? Egg(490, message: "导出视频失败")))
                            return
                        }
                        self.compressVideo(presetName: lastPreset, completion: completion, tryIfNeed: false)
                    } else {
                        if returnOriginalDataIfFailed {
                            guard let url = (self as? AVURLAsset)?.url else {
                                completion(.failure(Egg("无法获取到原始文件地址")))
                                return
                            }
                            do {
                                let data =  try Data(contentsOf: url)
                                try data.write(to: outputURL)
                                completion(.success(outputURL))
                            } catch let error {
                                completion(.failure(error))
                            }
                        } else {
                            completion(.failure(exportSession.error ?? Egg(490, message: "导出视频失败")))
                        }
                    }
                case .cancelled:
                    completion(.failure(exportSession.error ?? Egg(491, message:"取消视频导出")))
                default:
                    break
                }
            }
        }
    }
}


extension AVAsset {
    public struct VideoInfo {
        public enum VideoOrientation: Int {
            case r0, r90, r180, r270
        }
        
        public var size: CGSize
        public var orientation: VideoOrientation
        
        /// 每秒的帧率
        public var frameRate: Float
        public init() {
            size = .zero
            orientation = .r0
            frameRate = 0
        }
        public init(size: CGSize, orientation: VideoOrientation, frameRate: Float) {
            self.size = size
            self.orientation = orientation
            self.frameRate = frameRate
        }
    }
    
    public var videoInfo: VideoInfo? {
        guard let track = tracks(withMediaType: .video).first else {return nil}
        var info = VideoInfo()
        let t = track.preferredTransform
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0):
            info.orientation = .r90
        case (0, -1, 1, 0):
            info.orientation = .r270
        case (1, 0, 0, 1):
            info.orientation = .r0 // 电源键在上边时旋转角度是0
        case (-1, 0, 0, -1):
            info.orientation = .r180
        default:
            break
        }
        info.size = track.naturalSize
        info.frameRate = track.nominalFrameRate
#if DEBUG
        print("transform \((t.a, t.b, t.c, t.d)) size \(track.naturalSize)")
#endif
        return info
    }
}

extension AVURLAsset {
    public var videoPreviewImage: UIImage? {
        let assetGenerator = AVAssetImageGenerator(asset: self)
        assetGenerator.appliesPreferredTrackTransform = true
        let time = CMTimeMakeWithSeconds(0, preferredTimescale: 600)
        let actualTime = UnsafeMutablePointer<CMTime>.allocate(capacity: MemoryLayout.stride(ofValue: CMTime()))
        do {
            let imageRef = try assetGenerator.copyCGImage(at: time, actualTime: actualTime)
            let image = UIImage(cgImage: imageRef)
            return image
        } catch {
            return nil
        }
    }
}
