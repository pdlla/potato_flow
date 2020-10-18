{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RecursiveDo     #-}

module Potato.Flow.Reflex.EverythingWidgetSpec
  ( spec
  )
where

import           Relude                              hiding (empty, fromList)

import           Test.Hspec
import           Test.Hspec.Contrib.HUnit            (fromHUnitTest)
import           Test.HUnit

import           Reflex
import           Reflex.Test.Host

import           Potato.Flow
import           Potato.Flow.Reflex.Everything
import           Potato.Flow.Reflex.EverythingWidget
import           Potato.Flow.TestStates

import           Control.Monad.Fix
import qualified Data.IntMap                         as IM
import qualified Data.Sequence                       as Seq
import qualified Data.Text                           as T
import           Data.These

someState1 :: PFState
someState1 = PFState {
      _pFState_layers = Seq.fromList [0..5]
      , _pFState_directory = IM.fromList [(0, folderStart), (1, someSEltLabel), (2, someSEltLabel), (3, someSEltLabel), (4, someSEltLabel), (5, folderEnd)]
      , _pFState_canvas = someSCanvas
  }

-- simple bespoke testing
tool_network
  :: forall t m. (t ~ SpiderTimeline Global, m ~ SpiderHost Global)
  => (Event t Tool -> TestGuestT t m (Event t Tool))
tool_network ev = do
  everythingWidget <- holdEverythingWidget $ emptyEverythingWidgetConfig { _everythingWidgetConfig_selectTool = ev }
  return $ updated . _everythingWidget_tool $ everythingWidget

tool_test :: Test
tool_test = TestLabel "tool" $ TestCase $ do
  let
    -- note, starting value is TSelect
    bs = [Tool_Pan, Tool_Select, Tool_Pan, Tool_Pan, Tool_Box, Tool_Line, Tool_Text]
    expected = [Just Tool_Pan, Just Tool_Select, Just Tool_Pan, Nothing, Just Tool_Box, Just Tool_Line, Just Tool_Text]
    run = runAppSimple tool_network bs
  v <- liftIO run
  (join v) @?= expected

select_network
  :: forall t m. (t ~ SpiderTimeline Global, m ~ SpiderHost Global)
  => Event t (Bool, Selection) -> TestGuestT t m (Event t Selection)
select_network ev = do
  let
    addSelectEv = fmapMaybe (\(b,s) -> if b then Just s else Nothing) ev
    newSelectEv = fmapMaybe (\(b,s) -> if not b then Just s else Nothing) ev
  everythingWidget <- holdEverythingWidget $ emptyEverythingWidgetConfig {
      _everythingWidgetConfig_initialState = someState1
      , _everythingWidgetConfig_selectNew = newSelectEv
      , _everythingWidgetConfig_selectAdd = addSelectEv
    }
  return $ updated . _everythingWidget_selection $ everythingWidget

select_test :: Test
select_test = TestLabel "select" $ TestCase $ do
  let
    mySelection1 = Seq.fromList [(1,1,someSEltLabel)]
    mySelection2 = Seq.fromList [(2,2,someSEltLabel)]
    combined = Seq.fromList [(1,1,someSEltLabel), (2,2,someSEltLabel)]
    bs = [(False, mySelection1), (True, mySelection2), (True, mySelection1), (False, mySelection1), (True, Seq.empty), (False, Seq.empty)]
    expected = [Just mySelection1, Just combined, Just mySelection2, Just mySelection1, Nothing, Just (Seq.empty)]
    run = runAppSimple select_network bs
  v <- liftIO run
  (join v) @?= expected

-- generic testing
data EverythingWidgetCmd =
  EWCMouse LMouseData
  | EWCKeyboard KeyboardData
  | EWCTool Tool
  | EWCSelect Selection Bool -- true if add to selection
  | EWCNothing



everything_network_app
  :: forall t m. (t ~ SpiderTimeline Global, m ~ SpiderHost Global)
  => AppIn t () EverythingWidgetCmd -> TestGuestT t m (AppOut t EverythingCombined_DEBUG EverythingCombined_DEBUG)
everything_network_app (AppIn _ ev) = do
  let ewc = EverythingWidgetConfig  {
      _everythingWidgetConfig_initialState = emptyPFState

      , _everythingWidgetConfig_mouse = fforMaybe ev $ \case
        EWCMouse x -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_keyboard = fforMaybe ev $ \case
        EWCKeyboard x -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_selectTool = fforMaybe ev $ \case
        EWCTool x -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_selectNew = fforMaybe ev $ \case
        EWCSelect x False -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_selectAdd = fforMaybe ev $ \case
        EWCSelect x True -> Just x
        _ -> Nothing
    }
  everythingWidget <- holdEverythingWidget ewc
  let rDyn = _everythingWidget_everythingCombined_DEBUG everythingWidget
  return $ AppOut (current rDyn) (updated rDyn)


-- simplified version of above with no behavior, you can delete this
everything_network
  :: forall t m. (t ~ SpiderTimeline Global, m ~ SpiderHost Global)
  => Event t EverythingWidgetCmd -> TestGuestT t m (Event t EverythingCombined_DEBUG)
everything_network ev = do
  let ewc = EverythingWidgetConfig  {
      _everythingWidgetConfig_initialState = emptyPFState

      , _everythingWidgetConfig_mouse = fforMaybe ev $ \case
        EWCMouse x -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_keyboard = fforMaybe ev $ \case
        EWCKeyboard x -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_selectTool = fforMaybe ev $ \case
        EWCTool x -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_selectNew = fforMaybe ev $ \case
        EWCSelect x False -> Just x
        _ -> Nothing
      , _everythingWidgetConfig_selectAdd = fforMaybe ev $ \case
        EWCSelect x True -> Just x
        _ -> Nothing
    }
  everythingWidget <- holdEverythingWidget ewc
  return $ updated $ _everythingWidget_everythingCombined_DEBUG everythingWidget

data EverythingPredicate where
  EqPredicate :: (Show a, Eq a) => (EverythingCombined_DEBUG -> a) -> a -> EverythingPredicate
  FunctionPredicate :: (EverythingCombined_DEBUG -> (Text, Bool)) -> EverythingPredicate
  PFStateFunctionPredicate :: (PFState -> (Text, Bool)) -> EverythingPredicate
  AlwaysPass :: EverythingPredicate
  Combine :: [EverythingPredicate] -> EverythingPredicate

testEverythingPredicate :: EverythingPredicate -> EverythingCombined_DEBUG -> Bool
testEverythingPredicate (EqPredicate f a) e     = f e == a
testEverythingPredicate (FunctionPredicate f) e = snd $ f e
testEverythingPredicate (PFStateFunctionPredicate f) e = snd . f $ _everythingCombined_pFState e
testEverythingPredicate AlwaysPass _            = True
testEverythingPredicate (Combine xs) e          = all id . map (\p -> testEverythingPredicate p e) $ xs

showEverythingPredicate :: EverythingPredicate -> EverythingCombined_DEBUG -> Text
showEverythingPredicate (EqPredicate f a) e = "expected: " <> show a <> " got: " <> show (f e)
showEverythingPredicate (FunctionPredicate f) e = fst $ f e
showEverythingPredicate (PFStateFunctionPredicate f) e = fst . f $ _everythingCombined_pFState e
showEverythingPredicate AlwaysPass _ = "always pass"
showEverythingPredicate (Combine xs) e = "[" <> foldr (\p acc -> showEverythingPredicate p e <> ", " <> acc) "" xs <> "]"

checkNumElts :: Int -> PFState -> (Text, Bool)
checkNumElts n PFState {..} = (t,r) where
  ds = IM.size _pFState_directory
  ls = Seq.length _pFState_layers
  r = ds == n && ls == n
  t = "expected: " <> show n <> " dir: " <> show ds <> " layers: " <> show ls

everything_basic_test :: Test
everything_basic_test = TestLabel "everything_basic" $ TestCase $ do
  -- TODO test something
  let
    bs = [
        EWCNothing -- test basic panning
        , EWCTool Tool_Pan
        -- drag to (1, 1) and release
        , EWCMouse (LMouseData (V2 0 0) False MouseButton_Left)
        , EWCMouse (LMouseData (V2 1 1) True MouseButton_Left)
        -- drag to (10, 15) and cancel without releasing
        , EWCMouse (LMouseData (V2 0 0) False MouseButton_Left)
        , EWCMouse (LMouseData (V2 (-1) (-1)) False MouseButton_Left)
        , EWCMouse (LMouseData (V2 9 14) False MouseButton_Left)
        , EWCKeyboard (KeyboardData KeyboardKey_Esc KeyboardKeyType_Click)

        , EWCNothing -- create elt
        , EWCTool Tool_Box
        -- drag from (1,1) to (10,10) and release
        , EWCMouse (LMouseData (V2 1 1) False MouseButton_Left)
        , EWCMouse (LMouseData (V2 10 10) True MouseButton_Left)
        , EWCNothing -- dummy to check state

        -- TODO modify created elt
        -- check in layers and check render

        -- TODO delete the elt
        -- check in layers and check render
      ]

    expected = [
        AlwaysPass -- very basic panning
        , (EqPredicate _everythingCombined_selectedTool Tool_Pan)
        , (EqPredicate _everythingCombined_pan (V2 0 0))
        , (EqPredicate _everythingCombined_pan (V2 1 1))
        , (EqPredicate _everythingCombined_pan (V2 1 1))
        , (EqPredicate _everythingCombined_pan (V2 0 0))
        , (EqPredicate _everythingCombined_pan (V2 10 15))
        , (EqPredicate _everythingCombined_pan (V2 1 1))

        , AlwaysPass -- create elt
        , (EqPredicate _everythingCombined_selectedTool Tool_Box)
        -- TODO move to helper function
        , (FunctionPredicate (
          (\case
            FrontendOperation_Manipulate _ _ -> ("",True)
            o -> ("Expected FrontendOperation_Manipulate got " <> show o, False))
          . _everythingCombined_lastOperation))
        , (FunctionPredicate (
          (\case
            FrontendOperation_Manipulate _ _ -> ("",True)
            o -> ("Expected FrontendOperation_Manipulate got " <> show o, False))
          . _everythingCombined_lastOperation))
        , Combine [
            PFStateFunctionPredicate (checkNumElts 1)
          ]
      ]



    --run = runAppSimple everything_network bs
    run = runApp everything_network_app () (fmap (Just . That) bs)
  values :: [[(EverythingCombined_DEBUG, Maybe EverythingCombined_DEBUG)]]
    <- liftIO run

  -- expect only 1 tick per event
  forM values $ \x -> length x @?= 1

  -- expect correct number of outputs
  length values @?= length expected

  -- expect each output matches predicate
  -- if no output event, uses output behavior to test predicate
  forM_ (zip3 (join values) expected [0..]) $ \((b, me), p, i) -> let
      testfn ewcd = (assertBool . T.unpack) ((showEverythingPredicate p ewcd) <> " for " <> show i) (testEverythingPredicate p ewcd)
    in case me of
      Just e  -> testfn e
      Nothing -> testfn b







spec :: Spec
spec = do
  describe "EverythingWidget" $ do
    fromHUnitTest $ tool_test
    fromHUnitTest $ select_test
    fromHUnitTest $ everything_basic_test
