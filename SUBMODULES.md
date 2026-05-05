# Optional OSG/MyGUI Source Trees

OpenMW can build internal OSG and MyGUI in two ways:

1. default: CMake downloads the upstream sources with `FetchContent`
2. optional: local source trees in `extern/osg` and `extern/mygui`

Initialize the optional trees with:

```sh
git submodule update --init extern/osg extern/mygui
```

Notes:

- `extern/osg` is useful when you want to carry a local Darwin/PPC-patched OSG tree.
- `extern/mygui` is optional. If it is absent, CMake falls back to the upstream MyGUI archive.
- If both trees are absent, the build still works through `FetchContent`.
