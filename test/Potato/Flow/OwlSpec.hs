module Potato.Flow.OwlSpec (
  spec
) where


import           Relude

import           Test.Hspec

import qualified Data.Sequence            as Seq
import           Potato.Flow.Owl
import           Potato.Flow.TestStates
import           Potato.Flow.State

spec :: Spec
spec = do
  describe "Owl" $ do
    let
      owlDirectory2 = owlDirectory_fromOldState (_pFState_directory pfstate_basic2) (_pFState_layers pfstate_basic2)
    it "basic" $ do
      --forM (owlDirectory_prettyPrint owlDirectory2) print
      (Seq.length (owlDirectory_topSuperOwls owlDirectory2) `shouldBe` 1)
      owlDirectory_owlCount owlDirectory2 `shouldBe` 9
    it "owliterateall" $ do
      toList (fmap _superOwl_id (owliterateall owlDirectory2)) `shouldBe` [0,1,2,3,4,5,7,8,9]
    {-it "owlDirectory_addSuperOwl" $ do
      let
        spot =

      owlDirectory_addSuperOwl :: OwlSpot -> SuperOwl -> OwlDirectory -> OwlDirectory-}
