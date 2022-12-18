{-# LANGUAGE RecordWildCards #-}

module Potato.Flow.Controller.Manipulator.Pan (
  PanHandler(..)
) where

import           Relude

import           Potato.Flow.Controller.Handler
import           Potato.Flow.Controller.Input
import           Potato.Flow.Controller.Types
import           Potato.Flow.Math

import           Data.Default


data PanHandler = PanHandler {
    _panHandler_pan :: XY -- TODO Rename to panDelta
    , _panHandler_maybePrevHandler :: Maybe SomePotatoHandler
  }

instance Default PanHandler where
  def = PanHandler { 
      _panHandler_pan = 0
      , _panHandler_maybePrevHandler = Nothing
    }

instance PotatoHandler PanHandler where
  pHandlerName _ = handlerName_pan
  pHandleMouse ph@PanHandler {..} PotatoHandlerInput {..} (RelMouseDrag MouseDrag {..}) = Just $ case _mouseDrag_state of
    MouseDragState_Cancelled -> def { _potatoHandlerOutput_pan = Just $ - _panHandler_pan }
    MouseDragState_Down -> def { _potatoHandlerOutput_nextHandler = Just $ SomePotatoHandler ph }
    x -> def {
        _potatoHandlerOutput_nextHandler = case _mouseDrag_state of
          MouseDragState_Dragging -> Just $ SomePotatoHandler ph { _panHandler_pan = delta }
          MouseDragState_Up -> case _panHandler_maybePrevHandler of
            Nothing -> Just $ SomePotatoHandler (def :: PanHandler)
            Just x -> Just x
          _ -> error "not posible"
        , _potatoHandlerOutput_pan = Just (delta - _panHandler_pan)
        --, _potatoHandlerOutput_pan = trace (show x <> " delta " <> show delta <> " pan " <> show _panHandler_pan <> " from " <> show _mouseDrag_from <> " to " <> show _mouseDrag_to) $ Just (delta - _panHandler_pan)
      } where delta = _mouseDrag_to - _mouseDrag_from

  -- TODO keyboard pan
  pHandleKeyboard PanHandler {..} PotatoHandlerInput {..} _ = Nothing

  -- refresh the underlying handler if there is one
  pRefreshHandler ph@PanHandler {..} phi = Just $ SomePotatoHandler ph {
      _panHandler_maybePrevHandler = join $ fmap (flip pRefreshHandler phi) _panHandler_maybePrevHandler
    }

  -- render the underlying handler if there is one
  pRenderHandler ph@PanHandler {..} phi = case _panHandler_maybePrevHandler of
    Nothing -> def
    Just x -> pRenderHandler x phi

  -- always active so we never replace pan handler with new selection from changes (which should never happen anyways)
  pIsHandlerActive _ = True

  pHandlerTool _ = Just Tool_Pan
