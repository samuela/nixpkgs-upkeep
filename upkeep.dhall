let WithClause =
      { Type =
          { extra_nix_config : Optional Text
          , nix_path : Optional Text
          , path : Optional Text
          , repository : Optional Text
          , token : Optional Text
          }
      , default =
        { extra_nix_config = None Text
        , nix_path = None Text
        , path = None Text
        , repository = None Text
        , token = None Text
        }
      }

let Step =
      { Type =
          { env : Optional { GH_TOKEN : Text }
          , name : Optional Text
          , run : Optional Text
          , uses : Optional Text
          , `with` : Optional WithClause.Type
          , working-directory : Optional Text
          }
      , default =
        { env = None { GH_TOKEN : Text }
        , name = None Text
        , run = None Text
        , uses = None Text
        , `with` = None WithClause.Type
        , working-directory = None Text
        }
      }

let installNix =
      Step::{
      , uses = Some "cachix/install-nix-action@v16"
      , `with` = Some WithClause::{
        , extra_nix_config = Some "experimental-features = nix-command flakes"
        , nix_path = Some "nixpkgs=channel:nixos-unstable"
        }
      }

let checkoutNixpkgsUpkeep =
      Step::{
      , name = Some "Checkout nixpkgs-upkeep"
      , uses = Some "actions/checkout@v2"
      , `with` = Some WithClause::{ path = Some "nixpkgs-upkeep" }
      }

let checkoutNixpkgs =
      Step::{
      , name = Some "Checkout nixpkgs"
      , uses = Some "actions/checkout@v2"
      , `with` = Some WithClause::{
        , path = Some "nixpkgs"
        , repository = Some "NixOS/nixpkgs"
        , token = Some "\${{ secrets.GH_TOKEN }}"
        }
      }

let checkVersion =
      \(attr : Text) ->
        Step::{
        , name = Some "Check current package version"
        , run = Some
            ''
            PACKAGE="${attr}"
            PRE_VERSION="$(nix eval --raw -f . $PACKAGE.version)"
            echo "PACKAGE=$PACKAGE" >> $GITHUB_ENV
            echo "PRE_VERSION=$PRE_VERSION" >> $GITHUB_ENV
            ''
        , working-directory = Some "./nixpkgs"
        }

let nixBuild =
      \(attr : Text) ->
        Step::{
        , run = Some "nix-build -A ${attr}"
        , working-directory = Some "./nixpkgs"
        }

let canary =
      Step::{
      , name = Some "build canary"
      , run = Some
          ''
          GH_TOKEN=$GH_TOKEN ./canary.py --nixpkgs ../nixpkgs --attr $PACKAGE
          ''
      , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
      , working-directory = Some "./nixpkgs-upkeep"
      }

let gitDiff =
      Step::{ run = Some "git diff", working-directory = Some "./nixpkgs" }

let allowUnfree =
      Step::{
      , name = Some "Allow unfree"
      , run = Some
          ''
          mkdir -p ~/.config/nixpkgs/
          echo "{ allowUnfree = true; }" > ~/.config/nixpkgs/config.nix
          ''
      }

let Job =
      { Type = { runs-on : Text, steps : List Step.Type }
      , default.runs-on = "ubuntu-latest"
      }

let basicCanary =
      \(attr : Text) ->
        Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , allowUnfree
          , checkVersion attr
          , canary
          ]
        }

let customUpdateScript =
      \(scriptName : Text) ->
      \(cwd : Text) ->
        Step::{
        , name = Some "Run custom update-script"
        , run = Some
            ''
            cp ./nixpkgs-upkeep/${scriptName} ./nixpkgs/${cwd}
            chmod +x ./nixpkgs/${cwd}/update-matplotlib.py
            ./nixpkgs/${cwd}/update-matplotlib.py
            rm ./nixpkgs/${cwd}/update-matplotlib.py
            ''
        }

let createPR =
      \(attr : Text) ->
      \(targetBranch : Text) ->
        Step::{
        , name = Some "Create PR"
        , run = Some
            ''
            GH_TOKEN="$GH_TOKEN" \
              TARGET_BRANCH="${targetBranch}" \
              PACKAGE="${attr}" \
              PRE_VERSION="$PRE_VERSION" \
              TESTED_OTHER_LINUX="true" \
              GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
              ./../nixpkgs-upkeep/create-pr.sh
            ''
        , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
        , working-directory = Some "./nixpkgs"
        }

in  { jobs =
      { dm-haiku = basicCanary "python3Packages.dm-haiku"
      , elegy = basicCanary "python3Packages.elegy"
      , flax = basicCanary "python3Packages.flax"
      , ipython = basicCanary "python3Packages.ipython"
      , jax = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.jax"
          , canary
          , customUpdateScript
              "update-jax.py"
              "pkgs/development/python-modules/jax"
          , gitDiff
          , nixBuild "python3Packages.jax"
          , createPR "python3Packages.jax" "master"
          ]
        }
      , jaxlib = basicCanary "python3Packages.jaxlib"
      , jaxlibWithCuda = basicCanary "python3Packages.jaxlibWithCuda"
      , jmp = basicCanary "python3Packages.jmp"
      , julia_17-bin = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "julia_17-bin"
          , canary
          , customUpdateScript
              "update-julia-1.7.py"
              "pkgs/development/compilers/julia"
          , gitDiff
          , nixBuild "julia_17-bin"
          , createPR "julia_17-bin" "master"
          ]
        }
      , matplotlib = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.matplotlib"
          , canary
          , customUpdateScript
              "update-matplotlib.py"
              "pkgs/development/python-modules/matplotlib"
          , gitDiff
          , nixBuild "python3Packages.matplotlib"
          , createPR "python3Packages.matplotlib" "staging"
          ]
        }
      , optax = basicCanary "python3Packages.optax"
      , plexamp = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , allowUnfree
          , Step::{
            , name = Some "Check current package version before update script"
            , run = Some
                ''
                PRE_VERSION="$(nix-instantiate --eval -E "with import ./. {}; lib.getVersion plexamp" --json | jq -r)"
                echo "PRE_VERSION=$PRE_VERSION" >> $GITHUB_ENV
                ''
            , working-directory = Some "./nixpkgs"
            }
          , Step::{
            , run = Some
                "./nixpkgs/pkgs/applications/audio/plexamp/update-plexamp.sh"
            }
          , gitDiff
          , nixBuild "plexamp"
          , createPR "plexamp" "master"
          ]
        }
      , plotly = basicCanary "python3Packages.plotly"
      , spotify = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , allowUnfree
          , Step::{
            , name = Some "Check current package version before update script"
            , run = Some
                ''
                PRE_VERSION="$(nix eval --raw -f . spotify-unwrapped.version)"
                echo "PRE_VERSION=$PRE_VERSION" >> $GITHUB_ENV
                ''
            , working-directory = Some "./nixpkgs"
            }
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                git config --global user.email "foo@bar.com"
                git config --global user.name "upkeep-bot"
                before_commit=$(git rev-parse HEAD)
                ./pkgs/applications/audio/spotify/update.sh
                after_commit=$(git rev-parse HEAD)
                if [ $before_commit != $after_commit ]; then
                  git reset "HEAD^"
                fi
                ''
            , working-directory = Some "./nixpkgs"
            }
          , gitDiff
          , nixBuild "spotify"
          , createPR "spotify-unwrapped" "master"
          ]
        }
      , tensorflow = basicCanary "python3Packages.tensorflow"
      , tensorflow-datasets = basicCanary "python3Packages.tensorflow-datasets"
      , tqdm = basicCanary "python3Packages.tqdm"
      , treeo = basicCanary "python3Packages.treeo"
      , treex = basicCanary "python3Packages.treex"
      , vscode = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , allowUnfree
          , checkVersion "vscode"
          , Step::{
            , run = Some
                "./nixpkgs/pkgs/applications/editors/vscode/update-vscode.sh"
            }
          , gitDiff
          , nixBuild "vscode"
          , createPR "vscode" "master"
          ]
        }
      , vscodium = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "vscodium"
          , Step::{
            , run = Some
                "./nixpkgs/pkgs/applications/editors/vscode/update-vscodium.sh"
            }
          , gitDiff
          , nixBuild "vscodium"
          , createPR "vscodium" "master"
          ]
        }
      , wandb = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.wandb"
          , canary
          , customUpdateScript
              "update-wandb.py"
              "pkgs/development/python-modules/wandb"
          , gitDiff
          , nixBuild "python3Packages.wandb"
          , createPR "python3Packages.wandb" "master"
          ]
        }
      }
    , name = "upkeep"
    , on =
      { push.branches = [ "main" ], schedule = [ { cron = "0 0,12 * * *" } ] }
    }
