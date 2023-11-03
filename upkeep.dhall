let WithClause =
      < InstallNix : { extra_nix_config : Text, nix_path : Text }
      | Cachix : { name : Text, authToken : Text }
      | Checkout :
          { path : Text, repository : Optional Text, token : Optional Text }
      | MaximizeBuildSpace :
          { remove-dotnet : Text
          , remove-android : Text
          , remove-haskell : Text
          , remove-codeql : Text
          , remove-docker-images : Text
          }
      >

let Step =
      { Type =
          { env : Optional { GH_TOKEN : Text }
          , name : Optional Text
          , run : Optional Text
          , uses : Optional Text
          , `with` : Optional WithClause
          , working-directory : Optional Text
          }
      , default =
        { env = None { GH_TOKEN : Text }
        , name = None Text
        , run = None Text
        , uses = None Text
        , `with` = None WithClause
        , working-directory = None Text
        }
      }

let installNix =
      Step::{
      , uses = Some "cachix/install-nix-action@v22"
      , `with` = Some
          ( WithClause.InstallNix
              { extra_nix_config = "experimental-features = nix-command flakes"
              , nix_path = "nixpkgs=channel:nixos-unstable"
              }
          )
      }

let nixInfo =
      Step::{
      , name = Some "nix-info"
      , run = Some "nix-shell -p nix-info --run 'nix-info -m'"
      }

let checkoutNixpkgsUpkeep =
      Step::{
      , name = Some "Checkout nixpkgs-upkeep"
      , uses = Some "actions/checkout@v3"
      , `with` = Some
          ( WithClause.Checkout
              { path = "nixpkgs-upkeep"
              , token = None Text
              , repository = None Text
              }
          )
      }

let checkoutNixpkgs =
      Step::{
      , name = Some "Checkout nixpkgs"
      , uses = Some "actions/checkout@v3"
      , `with` = Some
          ( WithClause.Checkout
              { path = "nixpkgs"
              , repository = Some "NixOS/nixpkgs"
              , token = Some "\${{ secrets.GH_TOKEN }}"
              }
          )
      }

let checkVersion =
      \(attr : Text) ->
        Step::{
        , name = Some "Check current package version"
        , run = Some
            ''
            PRE_VERSION="$(nix eval --raw --file . ${attr}.version)"
            echo "Current version: $PRE_VERSION"
            echo "PRE_VERSION=$PRE_VERSION" >> $GITHUB_ENV
            ''
        , working-directory = Some "./nixpkgs"
        }

let canary =
      \(attr : Text) ->
        Step::{
        , name = Some "build canary"
        , run = Some
            ''
            GH_TOKEN=$GH_TOKEN ./canary.py --nixpkgs ../nixpkgs --attr ${attr}
            ''
        , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
        , working-directory = Some "./nixpkgs-upkeep"
        }

let gitDiff =
      Step::{ run = Some "git diff", working-directory = Some "./nixpkgs" }

let nixpkgsConfig =
      Step::{
      , name = Some "Set ~/.config/nixpkgs/config.nix"
      , run = Some
          ''
          mkdir -p ~/.config/nixpkgs/
          echo '{ allowUnfree = true; cudaSupport = true; cudaCapabilities = ["8.0"]; }' > ~/.config/nixpkgs/config.nix
          ''
      }

let addOverlay =
      Step::{
      , name = Some "Add CUDA/MKL overlay"
      , run = Some
          ''
          mkdir -p ~/.config/nixpkgs/overlays/
          cp ./nixpkgs-upkeep/overlay.nix ~/.config/nixpkgs/overlays/
          ''
      }

let Job =
      { Type = { runs-on : Text, steps : List Step.Type }
      , default.runs-on = "ubuntu-latest"
      }

let cachix =
      Step::{
      , uses = Some "cachix/cachix-action@v12"
      , `with` = Some
          ( WithClause.Cachix
              { name = "ploop"
              , authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}"
              }
          )
      }

let maximize-build-space =
      Step::{
      , uses = Some "easimon/maximize-build-space@master"
      , `with` = Some
          ( WithClause.MaximizeBuildSpace
              { remove-dotnet = "true"
              , remove-android = "true"
              , remove-haskell = "true"
              , remove-codeql = "true"
              , remove-docker-images = "true"
              }
          )
      }

let intro =
      [ maximize-build-space
      , Step::{ run = Some "lscpu" }
      , installNix
      , nixInfo
      , cachix
      , checkoutNixpkgsUpkeep
      , checkoutNixpkgs
      , addOverlay
      , nixpkgsConfig
      ]

let basicCanary =
      \(attr : Text) ->
        Job::{ steps = intro # [ checkVersion attr, canary attr ] }

let customUpdateScript =
      \(scriptName : Text) ->
      \(cwd : Text) ->
        Step::{
        , name = Some "Run custom update-script"
        , run = Some
            ''
            cp ./nixpkgs-upkeep/${scriptName} ./nixpkgs/${cwd}
            chmod +x ./nixpkgs/${cwd}/${scriptName}
            ./nixpkgs/${cwd}/${scriptName}
            rm ./nixpkgs/${cwd}/${scriptName}
            ''
        }

let createPR =
      \(attr : Text) ->
        Step::{
        , name = Some "Create PR"
        , run = Some
            ''
            GH_TOKEN="$GH_TOKEN" \
              PACKAGE="${attr}" \
              PRE_VERSION="$PRE_VERSION" \
              GITHUB_WORKFLOW_URL="https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
              ./../nixpkgs-upkeep/create-pr.sh
            ''
        , env = Some { GH_TOKEN = "\${{ secrets.GH_TOKEN }}" }
        , working-directory = Some "./nixpkgs"
        }

in  { jobs =
      { augmax = basicCanary "python3Packages.augmax"
      , einops = basicCanary "python3Packages.einops"
      , flax = basicCanary "python3Packages.flax"
      , ipython = basicCanary "python3Packages.ipython"
      , jax = basicCanary "python3Packages.jax"
      , jaxlib = basicCanary "python3Packages.jaxlib"
      , jaxlib-bin = basicCanary "python3Packages.jaxlib-bin"
      , jaxlibWithCuda = basicCanary "python3Packages.jaxlibWithCuda"
      , matplotlib = basicCanary "python3Packages.matplotlib"
      , optax = basicCanary "python3Packages.optax"
      , pandas = basicCanary "python3Packages.pandas"
      , plexamp = Job::{
        , steps =
              intro
            # [ Step::{
                , name = Some
                    "Check current package version before update script"
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
              , createPR "plexamp"
              ]
        }
      , plotly = basicCanary "python3Packages.plotly"
      , torch = basicCanary "python3Packages.torch"
      , torch-bin = basicCanary "python3Packages.torch-bin"
      , spotify = Job::{
        , steps =
              intro
            # [ checkVersion "spotify-unwrapped"
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
              , createPR "spotify-unwrapped"
              ]
        }
      , tensorflow = basicCanary "python3Packages.tensorflow"
      , tensorflow-bin = basicCanary "python3Packages.tensorflow-bin"
      , tensorflow-datasets = basicCanary "python3Packages.tensorflow-datasets"
      , tqdm = basicCanary "python3Packages.tqdm"
      , torchvision = basicCanary "python3Packages.torchvision"
      , vscode = Job::{
        , steps =
              intro
            # [ checkVersion "vscode"
              , Step::{
                , run = Some
                    "./nixpkgs/pkgs/applications/editors/vscode/update-vscode.sh"
                }
              , gitDiff
              , createPR "vscode"
              ]
        }
      , vscodium = Job::{
        , steps =
              intro
            # [ checkVersion "vscodium"
              , Step::{
                , run = Some
                    "./nixpkgs/pkgs/applications/editors/vscode/update-vscodium.sh"
                }
              , gitDiff
              , createPR "vscodium"
              ]
        }
      , wandb = Job::{
        , steps =
              intro
            # [ checkVersion "python3Packages.wandb"
              , canary "python3Packages.wandb"
              , customUpdateScript
                  "update-wandb.py"
                  "pkgs/development/python-modules/wandb"
              , gitDiff
              , createPR "python3Packages.wandb"
              ]
        }
      , yapf = basicCanary "yapf"
      }
    , name = "upkeep"
    , on = { push.branches = [ "main" ], schedule = [ { cron = "0 0 * * *" } ] }
    }
