//
//  OpusManager.swift
//  SwiftOpusCodec
//
//  Created by Farshad Ghafari on 5.03.2020.
//  Copyright © 2020 Farshad Ghafari. All rights reserved.
//

import AVFoundation
import opus


public final class Opus {

  // Opus parameters
  static let sampleRate                     : Double = 16_000.0
  static let channelCount                   = 1
  static let frameCount                     = 160
  static let isInterleaved                  = true
  static let application                    = 2049

}


public typealias AudioPCMBuffer = AVAudioPCMBuffer

protocol OpusManagerDelegate {
    func opusEncodedData(_ data: Data)
    func opusDecodedData(_ bufferOutput: AudioPCMBuffer)
}

class OpusManager {
    
    var engine: AVAudioEngine?
    var player:AVAudioPlayerNode = AVAudioPlayerNode()
    
    var delegate: OpusManagerDelegate?
    
    private var encoder: OpaquePointer!
    private var decoder: OpaquePointer!
    
    private let bus = 0
    
    private var inputBlock: AVAudioNodeTapBlock!
    
    private var bufferSemaphore: DispatchSemaphore!
    
    private var playbackQ = DispatchQueue(label: "Playback", qos: .userInteractive, attributes: [.concurrent])
    
    private var q = DispatchQueue(label: "Object", qos: .userInteractive, attributes: [.concurrent])
    
    private var encoderOutput = [UInt8](repeating: 0, count: Opus.frameCount)
    
    private var decoderOutput: AVAudioPCMBuffer!
    
    private var bufferOutput: AVAudioPCMBuffer!
    
    private var bufferInput: AVAudioPCMBuffer!
    
    private let converterOutputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                       sampleRate: Opus.sampleRate,
                                                       channels: AVAudioChannelCount(Opus.channelCount),
                                                       interleaved: Opus.isInterleaved)!
    private var _outputActive = false
    private var outputActive: Bool {
    get { return q.sync { _outputActive } }
    set { q.sync(flags: .barrier) { _outputActive = newValue } } }
    
    
    
    init() {
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, options: .init(rawValue: 0))
            try audioSession.setMode(.default)


        } catch {

            assertionFailure("AVAudioSession setup error: \(error)")
        }
        

        createBuffers()
        createInputBlock()
        createOpusObjects()
    }

    func stopInput() {
        
        // remove the Tap
        engine!.inputNode.removeTap(onBus: bus)

        // stop the output
        outputActive = false

        // stop and deallocate the engine
        engine!.stop()
        engine = nil
        
        player.stop()
    }
    
    func startInput() {
        
        // create the engine
        engine = AVAudioEngine()
        
        let input = engine!.inputNode
        engine!.attach(player)
         
        // Clear buffer
        clearBuffers()
         
        let inputFormat = input.inputFormat(forBus: bus)
        engine!.connect(player, to: engine!.mainMixerNode, format: inputFormat)
         
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 10)
        let format = engine!.inputNode.outputFormat(forBus: bus)
         
                 
        bufferSemaphore = DispatchSemaphore(value: 0)
        outputActive = true
        startOutput()
         
        engine!.inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: inputBlock)
         
        // prepare & start the engine
        engine!.prepare()
        try! engine!.start()
        
        player.play()
    }
    
         
    func decode(data: Data) {
                    
        let encodedData: [UInt8] = data.map { $0 }
        
        // ------------------ DECODE ------------------
                       
        let decodedOutputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: Opus.sampleRate,
                                                channels: AVAudioChannelCount(Opus.channelCount),
                                                interleaved: Opus.isInterleaved)!
   
        let decoderOutput = AVAudioPCMBuffer(pcmFormat: decodedOutputFormat,
                                             frameCapacity: AVAudioFrameCount(Opus.frameCount))!
   
        decoderOutput.frameLength = decoderOutput.frameCapacity
   
        let decodedFrames = opus_decode_float(self.decoder,
                                              encodedData,//self.encoderOutput,
                                              Int32(Opus.frameCount),//Int32(encodedFrames),
                                              decoderOutput.floatChannelData![0],
                                              Int32(Opus.frameCount),
                                              Int32(0))
   
       
       
        print("decoded frames =======> \(decodedFrames)\n")
        self.player.scheduleBuffer(decoderOutput)
        self.delegate?.opusDecodedData(decoderOutput)

    }
}


private extension OpusManager {
    
    private func clearBuffers() {

       // clear the buffers
       memset(bufferInput.floatChannelData![0], 0, Int(bufferInput.frameLength) * MemoryLayout<Float>.size * Opus.channelCount)
       memset(bufferOutput.floatChannelData![0], 0, Int(bufferOutput.frameLength) * MemoryLayout<Float>.size * Opus.channelCount)
       memset(decoderOutput.floatChannelData![0], 0, Int(decoderOutput.frameLength) * MemoryLayout<Float>.size * Opus.channelCount)
       
     }
    
    func createBuffers() {
        
        bufferOutput = AVAudioPCMBuffer(pcmFormat: converterOutputFormat,
                                         frameCapacity: AVAudioFrameCount(Opus.frameCount))!
        bufferOutput.frameLength = bufferOutput.frameCapacity
        
        bufferInput = AVAudioPCMBuffer(pcmFormat: converterOutputFormat,
                                         frameCapacity: AVAudioFrameCount(Opus.frameCount))!
        bufferInput.frameLength = bufferOutput.frameCapacity
        
        decoderOutput = AVAudioPCMBuffer(pcmFormat: converterOutputFormat,
                                          frameCapacity: AVAudioFrameCount(Opus.frameCount))!
        decoderOutput.frameLength = decoderOutput.frameCapacity
    }
    
    
    func startOutput() {
        
        playbackQ.async {
            
            while self.outputActive {
            
                self.bufferSemaphore.wait()
            
                
                for i in stride(from: 0, to: Int(self.bufferInput.frameLength), by: Opus.frameCount) {
                
                    // ------------------ ENCODE ------------------
            
                    let encodedFrames = opus_encode_float(self.encoder,
                                                          &self.bufferInput.floatChannelData![0][i],
                                                          Int32(Opus.frameCount),
                                                          &self.encoderOutput,
                                                          Int32(28))
                    
                
                    
                    
                    
                    if encodedFrames < 0 { print("Encoder error - " + String(cString: opus_strerror(encodedFrames))) }
                
                    print("encoded frames =======> \(encodedFrames)\n")
                
                
                    let data = Data(bytes: self.encoderOutput, count: self.encoderOutput.count)
                    self.delegate?.opusEncodedData(data)
                }
            }
        }
    }
    
    
    private func createInputBlock() {
      
      inputBlock = { [unowned self] (inputBuffer, time) in
        
        
            
            self.bufferInput = inputBuffer
            
            self.bufferSemaphore.signal()

      }
    }
    
    func createOpusObjects() {
        
      // create the Opus encoder
      var opusError : Int32 = 0
      self.encoder = opus_encoder_create(Int32(Opus.sampleRate),
                                   Int32(Opus.channelCount),
                                   Int32(Opus.application),
                                   &opusError)
      if opusError != OPUS_OK { fatalError("Unable to create OpusEncoder, error = \(opusError)") }
    
      // create the Opus decoder
      self.decoder = opus_decoder_create(Int32(Opus.sampleRate),
                                   Int32(Opus.channelCount),
                                   &opusError)
      if opusError != 0 { fatalError("Unable to create OpusDecoder, error = \(opusError)") }
   
  
    }
    
}

