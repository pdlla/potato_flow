{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RecursiveDo     #-}

module Potato.Flow.Reflex.Entry (
  PFConfig(..)
  , PFOutput(..)
  , holdPF
) where

import           Relude

import           Reflex
import           Reflex.Data.ActionStack
import           Reflex.Data.Directory
import           Reflex.Potato.Helpers

import           Data.Aeson
import qualified Data.ByteString.Lazy           as LBS
import           Data.Dependent.Sum             ((==>))
import qualified Data.List.NonEmpty             as NE

import           Potato.Flow.Reflex.Cmd
import           Potato.Flow.Reflex.Layers
import           Potato.Flow.Reflex.REltFactory
import           Potato.Flow.Reflex.RElts
import           Potato.Flow.SElts


import           Control.Monad.Fix

-- loading new workspace stufff
type LoadFileEvent t =  Event t LBS.ByteString
type SetWSEvent t = Event t SEltTree

loadWSFromFile :: (Reflex t) => LoadFileEvent t -> SetWSEvent t
loadWSFromFile = fmapMaybe decode

data PFConfig t = PFConfig {
  --_pfc_setWorkspace :: SetWSEvent t
  _pfc_addElt       :: Event t SEltLabel
  , _pfc_removeElt  :: Event t REltId
  --, _pfc_moveElt    :: Event t (REltId, LayerPos) -- new layer position (before or after removal?)
  --, _pfc_copy       :: Event t [REltId]
  --, _pfc_paste      :: Event t ([SElt], LayerPos)
  --, _pfc_duplicate  :: Event t [REltId]
  , _pfc_manipulate :: Event t ()

  , _pfc_undo       :: Event t ()
  , _pfc_redo       :: Event t ()
}

data PFOutput t = PFOutput {
  -- elements
  --_pfo_allElts     :: Behavior t (Map REltId (REltLabel t))

  _pfo_layers :: LayerTree t (REltLabel t)

  -- manipulators
}

holdPF ::
  forall t m a. (Reflex t, Adjustable t m, MonadHold t m, MonadFix m)
  => PFConfig t
  -> m (PFOutput t)
holdPF PFConfig {..} = mdo

  -- set up the action stack
  let
    actionStackConfig :: ActionStackConfig t (PFCmd t)
    actionStackConfig = ActionStackConfig {
      -- TODO
      _actionStackConfig_do      = never

      , _actionStackConfig_undo  = _pfc_undo
      , _actionStackConfig_redo  = _pfc_redo
      , _actionStackConfig_clear = never
    }
  actionStack :: ActionStack t (PFCmd t)
    <- holdActionStack actionStackConfig

  -- TODO map _pfc_removeElt and _pfc_manipulate to actionStack

  -- set up DirectoryIdAssigner
  let
    rEltsCreatedEv = fmap NE.fromList (_rEltFactory_rEltTree rEltFactory)
    directoryIdAssignerConfig = DirectoryIdAssignerConfig {
        _directoryIdAssignerConfig_assign = fmap (:|[]) _pfc_addElt
      }
  directoryIdAssigner :: DirectoryIdAssigner t (SEltLabel)
    <- holdDirectoryIdAssigner directoryIdAssignerConfig

  -- set up rEltFactory
  let
    rEltFactoryConfig = REltFactoryConfig {
        _rEltFactoryConfig_sEltTree = toList <$> _directoryIdAssigner_tag directoryIdAssigner _pfc_addElt
        , _rEltFactoryConfig_doManipulate = selectDo actionStack PFCManipulate
        , _rEltFactoryConfig_undoManipulate = selectUndo actionStack PFCManipulate
      }
    rEltFactory_action_newRElt :: Event t (PFCmd t)
    rEltFactory_action_newRElt = fmapMaybe (\x -> nonEmpty x >>= return . (PFCNewElts ==>)) $ _rEltFactory_rEltTree rEltFactory
  rEltFactory :: rEltFactory t
    <- holdREltFactory rEltFactoryConfig

  -- TODO connect relt factory to actions

  -- TODO set up add/remove events, these will get sent to both directory and layer tree

  -- set up Directory
  -- DELETE or move into layers probably?
  -- or do we want a separate directory for copy pasta type stuff?
  {-
  let
    directoryConfig = DirectoryConfig {
        -- TODO hook up to fanned outputs from actionStack
        _directoryMapConfig_add = never

        , _directoryMapConfig_remove = never
      }
  directory :: Directory t (REltLabel t)
    <- holdDirectory directoryConfig
  -}

  -- set up LayerTree
  let
    ltc_add_do_PFCNewElts = layerTree_attachEndPos layerTree $ fmap toList $ selectDo actionStack PFCNewElts
    ltc_add_undo_PFCDeleteElt = fmap (\(i,e) -> (i,[e])) $ selectUndo actionStack PFCDeleteElt

    -- new elts are guaranteed to be in sequence at the end
    ltc_remove_undo_PFCNewElts = fmap (\(i,es) -> snd $ mapAccumL (\acc _ -> (acc+1, acc+1)) (i-1-length es) es) $
      layerTree_attachEndPos layerTree $ selectUndo actionStack PFCNewElts
    ltc_remove_do_PFCDeleteElt = fmap (\(i,_) -> i :| []) $ selectDo actionStack PFCDeleteElt
    layerTreeConfig = LayerTreeConfig {
        -- DELETE
        --_layerTreeConfig_directory = _directoryMap_contents directory
        _layerTreeConfig_add = (\(p, elts) -> (p, fromList elts)) <$> leftmostwarn "_layerTreeConfig_add"
          [ltc_add_do_PFCNewElts, ltc_add_undo_PFCDeleteElt]
        , _layerTreeConfig_remove = leftmostwarn "_layerTreeConfig_remove" $
          [ltc_remove_undo_PFCNewElts, ltc_remove_do_PFCDeleteElt]
        --, _layerTreeConfig_copy = never
      }
  layerTree :: LayerTree t (REltLabel t)
    <- holdLayerTree layerTreeConfig

  return $
    PFOutput {
      _pfo_layers = layerTree
    }
