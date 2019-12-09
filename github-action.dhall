let haskellCi =
      https://raw.githubusercontent.com/vmchale/github-actions-dhall/master/haskell-ci.dhall sha256:54219f032460ae0c0300a3ae535747e4a9c89b5ffca74ad73a782fc5142f3d86

let installLibarchive =
      haskellCi.BuildStep.Name
        { name = "Install libarchive"
        , run =
            ''
            wget https://www.libarchive.org/downloads/libarchive-3.4.0.tar.gz
            tar xvf libarchive-3.4.0.tar.gz
            cd libarchive-3.4.0
            ./configure
            make -j
            sudo make install
            cd -
            ''
        }

in  haskellCi.generalCi
      [ haskellCi.checkout
      , haskellCi.haskellEnv haskellCi.matrixEnv
      , installLibarchive
      , haskellCi.cabalDeps
      , haskellCi.cabalBuild
      , haskellCi.BuildStep.Name { name = "Get test data", run = "make -j" }
      , haskellCi.cabalTest
      , haskellCi.cabalDoc
      ]
      ( Some
          { ghc =
              [ haskellCi.GHC.GHC844
              , haskellCi.GHC.GHC865
              , haskellCi.GHC.GHC881
              ]
          , cabal = [ haskellCi.Cabal.Cabal30 ]
          }
      ) : haskellCi.CI.Type