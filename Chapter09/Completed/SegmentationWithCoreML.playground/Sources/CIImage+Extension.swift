import UIKit

// MARK: - Convenience methods

public extension CIImage{

    /**
     - Returns: An instance of itself as a UIImage
     */
    public func toUIImage() -> UIImage?
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(self, from: self.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }

}

// MARK: - Image manipulation methods

public extension CIImage{
    
    public func centerCropAndResize(size:CGSize) -> CIImage?{
        var ox : CGFloat = 0
        var oy : CGFloat = 0

        let frameSize = min(self.extent.width, self.extent.height)

        if self.extent.width > self.extent.height{
            ox = (self.extent.width - self.extent.height)/2
        } else if self.extent.width < self.extent.height{
            oy = (self.extent.height - self.extent.width)/2
        }

        guard let frame = self.crop(rect:CGRect(x:ox,
                                                y:oy,
                                                width:frameSize,
                                                height:frameSize))?
            .resize(size:size) else{
            return nil
        }

        return frame
    }
    
    
    public func crop(rect:CGRect) -> CIImage?{
        let context = CIContext()
        guard let img = context.createCGImage(self, from: rect) else{
            return nil
        }
        return CIImage(cgImage: img)
    }
    
    /**
     Return a resized version of this instance (centered)
     */
    public func resize(size: CGSize) -> CIImage {
        // Calculate how much we need to scale down/up our image
        let scale = min(size.width,size.height) / min(self.extent.size.width, self.extent.size.height)
        
        let resizedImage = self.transformed(
            by: CGAffineTransform(
                scaleX: scale,
                y: scale))
        
        // Center the image
        let width = resizedImage.extent.width
        let height = resizedImage.extent.height
        let xOffset = (CGFloat(width) - size.width) / 2.0
        let yOffset = (CGFloat(height) - size.height) / 2.0
        let rect = CGRect(x: xOffset,
                          y: yOffset,
                          width: size.width,
                          height: size.height)
        
        return resizedImage
            .clamped(to: rect)
            .cropped(to: CGRect(
                x: 0, y: 0,
                width: size.width,
                height: size.height))
    }
}

// MARK : Byte array accessors

public extension CIImage{

    public func toByteArray() -> [UInt8]?{
        let colorSpace = self.colorSpace ?? CGColorSpaceCreateDeviceGray()
        return self.toByteArray(
            pixelFormatType:colorSpace.name == CGColorSpaceCreateDeviceGray().name
                ? kCVPixelFormatType_OneComponent8
                : kCVPixelFormatType_32ARGB,
            colorSpace: colorSpace)
    }
    
    /**
     Return the byte array data representation of itself
     */
    public func toByteArray(pixelFormatType: OSType, colorSpace: CGColorSpace) -> [UInt8]?{
        var pixelData : [UInt8]?
        
        let context = CIContext()
        
        // Create a dictionary requesting Core Graphics compatibility
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey:kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey:kCFBooleanTrue
            ] as CFDictionary
        
        // Create a pixel buffer at the size our model needs
        var nullablePixelBuffer: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(self.extent.size.width),
                                         Int(self.extent.size.height),
                                         pixelFormatType,
                                         attributes,
                                         &nullablePixelBuffer)
        
        // Evaluate staus and unwrap nullablePixelBuffer
        guard status == kCVReturnSuccess, let pixelBuffer = nullablePixelBuffer
            else {
                print("status != kCVReturnSuccess or nullablePixelBuffer is null")
                return nil
        }
        
        // Render the CIImage to our CVPixelBuffer and return it
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        context.render(self,
                       to: pixelBuffer,
                       bounds: CGRect(x: 0,
                                      y: 0,
                                      width: self.extent.size.width,
                                      height: self.extent.size.height),
                       colorSpace:colorSpace)
        
        
        // Get the number of bytes per row for the pixel buffer
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let dataSize = CVPixelBufferGetDataSize(pixelBuffer)
        
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            pixelData = Array<UInt8>(repeating: 0, count: dataSize)
            let buf = baseAddress.assumingMemoryBound(to: UInt8.self)
            for i in 0..<width*height{
                pixelData![i] = buf[i]
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelData
    }
}

// MARK: - ROI detection

public extension CIImage{
    
    public func getContentBoundingBox(flipY : Bool = false) -> CGRect?{
        let pixelFormatType = kCVPixelFormatType_OneComponent8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard var data = self.toByteArray(pixelFormatType:pixelFormatType, colorSpace:colorSpace) else{
                print("Failed to get byte array)")
                return nil
        }
        
        var minX : CGFloat = 0, minY : CGFloat = 0,
        maxX : CGFloat = self.extent.width, maxY : CGFloat = self.extent.height,
        width : Int = Int(self.extent.width), height : Int = Int(self.extent.height)
        
        if flipY{
            data.reverse() // flip the image around
        }
        
        let scanLineThreshold : Int = 1
        
        // bottom row scan
        for row in 0..<height{
            let sIdx = row * width
            var sum : Int = 0
            for col in 0..<width{
                sum += Int(data[sIdx + col]) > 0 ? 1 : 0
            }
            
            if sum >= scanLineThreshold{
                minY = CGFloat(row-1)
                break
            }
        }
        
        // top row scan
        for row in (0..<height).reversed(){
            let sIdx = row * width
            var sum : Int = 0
            for col in 0..<width{
                sum += Int(data[sIdx + col]) > 0 ? 1 : 0
            }
            
            if sum >= scanLineThreshold{
                maxY = CGFloat(row+1)
                break
            }
        }
        
        // left column scan
        for col in 0..<width{
            var sum : Int = 0
            
            for row in 0..<height{
                let idx = row * width + col
                sum += Int(data[idx]) > 0 ? 1 : 0
            }
            
            if sum >= scanLineThreshold{
                minX = CGFloat(col-1)
                break
            }
        }
        
        // right column scan
        for col in (0..<width).reversed(){
            var sum : Int = 0
            
            for row in 0..<height{
                let idx = row * width + col
                sum += Int(data[idx]) >= 200 ? 1 : 0
            }
            
            if sum >= scanLineThreshold{
                maxX = CGFloat(col+1)
                break
            }
        }
        
        let boundingBox = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY)
        
        if boundingBox.width <= 0 || boundingBox.height <= 0
            || boundingBox.width == self.extent.width
            || boundingBox.height == self.extent.height{
            return nil
        }
        
        return boundingBox
    }
}
