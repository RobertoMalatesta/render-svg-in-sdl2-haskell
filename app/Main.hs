{-# LANGUAGE OverloadedStrings #-}

module Main where

import Codec.Picture
import Codec.Picture.Types
import Data.Vector.Storable.Mutable (IOVector)
import Graphics.Rasterific.Svg
       (loadCreateFontCache, renderSvgDocument)
import Graphics.Svg (loadSvgFile)

import Data.Function (fix)
import Data.Word (Word8)

import Control.Monad as CM
import qualified Data.Vector.Generic.Mutable as GM
import Data.Vector.Storable (Vector)
import qualified Data.Vector.Storable as V

import Foreign.C.Types (CInt)
import qualified SDL
import SDL.Vect (Point(P), V2(V2), V4(V4))

import Control.Concurrent (threadDelay)
import SDL (($=))

import Paths_svg_loading (getDataFileName)

screenWidth, screenHeight :: CInt
(screenWidth, screenHeight) = (1280, 720)

-- SDL dependency: sudo apt-get install libsdl2-dev
main :: IO ()
main = do
  SDL.initialize [SDL.InitVideo, SDL.InitTimer, SDL.InitEvents]
    -- ensure render quality
  SDL.HintRenderScaleQuality $= SDL.ScaleLinear
  do renderQuality <- SDL.get SDL.HintRenderScaleQuality
     CM.when (renderQuality /= SDL.ScaleLinear) $
       putStrLn "Warning: Linear texture filtering not enabled!"
  window <-
    SDL.createWindow
      "Load and render SVG"
      SDL.defaultWindow
      { SDL.windowPosition = SDL.Centered
      , SDL.windowInitialSize = V2 screenWidth screenHeight
      }
  SDL.showWindow window
  renderer <-
    SDL.createRenderer
      window
      (-1)
      SDL.RendererConfig
      { SDL.rendererType = SDL.AcceleratedVSyncRenderer
      , SDL.rendererTargetTexture = True
      }
  SDL.rendererDrawColor renderer $= V4 maxBound maxBound maxBound maxBound
  SDL.clear renderer
  renderSvgExample renderer
  SDL.present renderer
  threadDelay 2000000
  SDL.destroyRenderer renderer
  SDL.destroyWindow window
  SDL.quit

rect x y w h = SDL.Rectangle (P $ V2 x y) (V2 w h)

renderSvgExample :: SDL.Renderer -> IO ()
renderSvgExample renderer = do
  mimage <- getDataFileName "thumbs-up.svg" >>= loadSVGImage
  case mimage of
    Nothing -> putStrLn "Image convertion failed."
    (Just image) -> do
      let surfaceSize :: V2 CInt
          surfaceSize = V2 1280 720
      surface <- createSurfaceFromSVG image surfaceSize
      texture <- SDL.createTextureFromSurface renderer surface
      V2 surfaceWidth surfaceHeight <- SDL.surfaceDimensions surface
      SDL.freeSurface surface
      let source = rect 0 0 surfaceWidth surfaceHeight
          dest = rect 0 0 surfaceWidth surfaceHeight
          angle = 0.0
          center = Nothing
          flipNone = V2 False False
      SDL.copyEx
        renderer
        texture
        (Just source)
        (Just dest)
        angle
        center
        flipNone
      SDL.destroyTexture texture

createSurfaceFromSVG :: Image PixelRGBA8 -> V2 CInt -> IO SDL.Surface
createSurfaceFromSVG image surfaceSize = do
  let rawImageData :: Vector Word8
      rawImageData = imageData image
      imWidth :: Int
      imWidth = imageWidth image
      pitch :: CInt
      pitch = fromIntegral imWidth
  mutableVector <- convertToMutableVector rawImageData
  SDL.createRGBSurfaceFrom mutableVector surfaceSize pitch SDL.RGBA8888

-- | as per https://github.com/haskell/vector/issues/175, there are some missing convertion functions
--   so we have to create one by hand
convertToMutableVector :: Vector Word8 -> IO (IOVector Word8)
convertToMutableVector v = do
  let len = V.length v
  mv <- GM.new len
  CM.forM_ [0 .. (len - 1)] $ \i -> GM.write mv i (v V.! i)
  return mv

loadSVGImage :: FilePath -> IO (Maybe (Image PixelRGBA8))
loadSVGImage filepath = do
  mdoc <- loadSvgFile filepath
  case mdoc of
    Nothing -> return Nothing
    Just doc -> do
      cache <- loadCreateFontCache "fonty-texture-cache"
      (finalImage, _) <- renderSvgDocument cache Nothing 96 doc
      return $ Just finalImage