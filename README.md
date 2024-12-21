# CETech1 minimal

> [!IMPORTANT]  
> Work in progressssssssssssss

## Getting started

1. Create repository from this template

2. [Get ZIG/ZLS](https://cyberegoorg.github.io/cetech1/getting-started.html#get-zig-zls)

3. Init

    ```sh
    git -C externals/cetech1/ submodule --init
    zig build init 
    ```

4. Build

    ```sh
    zig build
    ```

5. Create CETech1 project in `content` dir

    ```sh
    zig-out/bin/cetech1 --asset-root content/
    ```

6. Have fun
