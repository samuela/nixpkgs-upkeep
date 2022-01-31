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

in  { jobs =
      { dm-haiku = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.dm-haiku"
          , canary
          ]
        }
      , elegy = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.elegy"
          , canary
          ]
        }
      , flax = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.flax"
          , canary
          ]
        }
      , ipython = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.ipython"
          , canary
          ]
        }
      , jax = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.jax"
          , canary
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                cp nixpkgs-upkeep/update-jax.py nixpkgs/pkgs/development/python-modules/jax/update-jax.py
                ./nixpkgs/pkgs/development/python-modules/jax/update-jax.py
                rm nixpkgs/pkgs/development/python-modules/jax/update-jax.py
                ''
            }
          , gitDiff
          , nixBuild "python3Packages.jax"
          , Step::{
            , name = Some "Create PR"
            , working-directory = Some "./nixpkgs"
            , run = Some
                ''
                GH_TOKEN=$GH_TOKEN \
                  TARGET_BRANCH="master" \
                  PACKAGE=$PACKAGE \
                  PRE_VERSION=$PRE_VERSION \
                  TESTED_OTHER_LINUX="true" \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            }
          ]
        }
      , jaxlib = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.jaxlib"
          , canary
          ]
        }
      , jaxlibWithCuda = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , allowUnfree
          , checkVersion "python3Packages.jaxlibWithCuda"
          , canary
          ]
        }
      , jmp = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.jmp"
          , canary
          ]
        }
      , julia_17-bin = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "julia_17-bin"
          , canary
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                cp nixpkgs-upkeep/update-julia-1.7.py nixpkgs/pkgs/development/compilers/julia/update-julia-1.7.py
                ./nixpkgs/pkgs/development/compilers/julia/update-julia-1.7.py
                rm nixpkgs/pkgs/development/compilers/julia/update-julia-1.7.py
                ''
            }
          , gitDiff
          , nixBuild "julia_17-bin"
          , Step::{
            , name = Some "Create PR"
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , run = Some
                ''
                GH_TOKEN=$GH_TOKEN \
                  TARGET_BRANCH="master" \
                  PACKAGE=$PACKAGE \
                  PRE_VERSION=$PRE_VERSION \
                  TESTED_OTHER_LINUX="true" \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      , matplotlib = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.matplotlib"
          , canary
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                cp ./nixpkgs-upkeep/update-matplotlib.py ./nixpkgs/pkgs/development/python-modules/matplotlib
                chmod +x ./nixpkgs/pkgs/development/python-modules/matplotlib/update-matplotlib.py
                ./nixpkgs/pkgs/development/python-modules/matplotlib/update-matplotlib.py
                rm ./nixpkgs/pkgs/development/python-modules/matplotlib/update-matplotlib.py
                ''
            }
          , gitDiff
          , nixBuild "python3Packages.matplotlib"
          , Step::{
            , name = Some "Create PR"
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , run = Some
                ''
                PACKAGE="python3Packages.matplotlib" \
                  TARGET_BRANCH="staging" \
                  TESTED_OTHER_LINUX="true" \
                  PRE_VERSION=$PRE_VERSION \
                  GH_TOKEN=$GH_TOKEN \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      , optax = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.optax"
          , canary
          ]
        }
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
            , name = Some "Run custom update-script"
            , run = Some
                ''
                ./nixpkgs/pkgs/applications/audio/plexamp/update-plexamp.sh
                ''
            }
          , gitDiff
          , nixBuild "plexamp"
          , Step::{
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , name = Some "Create PR"
            , run = Some
                ''
                PACKAGE="plexamp" \
                  TARGET_BRANCH="master" \
                  TESTED_OTHER_LINUX="true" \
                  PRE_VERSION=$PRE_VERSION \
                  GH_TOKEN=$GH_TOKEN \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      , plotly = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.plotly"
          , canary
          ]
        }
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
          , Step::{
            , name = Some "Create PR"
            , run = Some
                ''
                PACKAGE="spotify-unwrapped" \
                  TARGET_BRANCH="master" \
                  TESTED_OTHER_LINUX="true" \
                  PRE_VERSION=$PRE_VERSION \
                  GH_TOKEN=$GH_TOKEN \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      , tensorflow = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.tensorflow"
          , canary
          ]
        }
      , tensorflow-datasets = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.tensorflow-datasets"
          , canary
          ]
        }
      , tqdm = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.tqdm"
          , canary
          ]
        }
      , treeo = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.treeo"
          , canary
          ]
        }
      , treex = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.treex"
          , canary
          ]
        }
      , vscode = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "vscode"
          , allowUnfree
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                ./pkgs/applications/editors/vscode/update-vscode.sh
                ''
            , working-directory = Some "./nixpkgs"
            }
          , gitDiff
          , nixBuild "vscode"
          , Step::{
            , name = Some "Create PR"
            , run = Some
                ''
                PACKAGE="vscode" \
                  TARGET_BRANCH="master" \
                  TESTED_OTHER_LINUX="true" \
                  PRE_VERSION=$PRE_VERSION \
                  GH_TOKEN=$GH_TOKEN \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      , vscodium = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "vscodium"
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                ./nixpkgs/pkgs/applications/editors/vscode/update-vscodium.sh
                ''
            }
          , gitDiff
          , nixBuild "vscodium"
          , Step::{
            , name = Some "Create PR"
            , run = Some
                ''
                PACKAGE="vscodium" \
                  TARGET_BRANCH="master" \
                  TESTED_OTHER_LINUX="true" \
                  PRE_VERSION=$PRE_VERSION \
                  GH_TOKEN=$GH_TOKEN \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      , wandb = Job::{
        , steps =
          [ installNix
          , checkoutNixpkgsUpkeep
          , checkoutNixpkgs
          , checkVersion "python3Packages.wandb"
          , canary
          , Step::{
            , name = Some "Run custom update-script"
            , run = Some
                ''
                cp nixpkgs-upkeep/update-wandb.py nixpkgs/pkgs/development/python-modules/wandb/update-wandb.py
                ./nixpkgs/pkgs/development/python-modules/wandb/update-wandb.py
                rm nixpkgs/pkgs/development/python-modules/wandb/update-wandb.py
                ''
            }
          , gitDiff
          , nixBuild "python3Packages.wandb"
          , Step::{
            , name = Some "Create PR"
            , run = Some
                ''
                GH_TOKEN=$GH_TOKEN \
                  TARGET_BRANCH="master" \
                  PACKAGE=$PACKAGE \
                  PRE_VERSION=$PRE_VERSION \
                  TESTED_OTHER_LINUX="true" \
                  GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
                  ./../nixpkgs-upkeep/create-pr.sh
                ''
            , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
            , working-directory = Some "./nixpkgs"
            }
          ]
        }
      }
    , name = "upkeep"
    , on =
      { push.branches = [ "main" ], schedule = [ { cron = "0 0,12 * * *" } ] }
    }
