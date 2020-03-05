//
//  ViewController.swift
//  SwiftOpusCodec
//
//  Created by Farshad Ghafari on 5.03.2020.
//  Copyright © 2020 Farshad Ghafari. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    
    @IBAction func startButtonPressed(_ sender: Any) {
        opusManager.startInput()
    }
    
    @IBAction func stopButtonPressed(_ sender: Any) {
        opusManager.stopInput()
    }
    
    
    
    var opusManager: OpusManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        opusManager = OpusManager()
        opusManager.delegate = self
        
        
    }
    
}


extension ViewController: OpusManagerDelegate {
    
    func opusEncodedData(_ data: Data) {
        opusManager.decode(data: data)
    }
    
    func opusDecodedData(_ bufferOutput: AudioPCMBuffer) {
        // TODO
        // handle buffer output
    }
    
    
}

