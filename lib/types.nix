{ wlib, lib }:
{
  /**
    A DAG LIST or (DAL) or `dependency list` of some inner type

    Arguments:
    - `elemType`: `type`

    Accepts a LIST of elements

    The elements should be of type `elemType`
    or sets of the type `{ data, name ? null, before ? [], after ? [] }`
    where the `data` field is of type `elemType`

    If a name is not given, it cannot be targeted by other values.

    Can be used in conjunction with `wlib.dag.topoSort` and `wlib.dag.sortAndUnwrap`

    Note, if the element type is a submodule then the `name` argument
    will always be set to the string "data" since it picks up the
    internal structure of the DAG values. To give access to the
    "actual" attribute name a new submodule argument is provided with
    the name `dagName`.

    The `config.optionname` value from the associated option
    will be normalized such that all items are DAG entries

    If you wish to alter the type, you may provide different options
    to `wlib.dag.dalWith` by updating this type `wlib.types.dalOf // { strict = false; }`
  */
  dalOf = wlib.dag.dalOf;

  /**
    A directed acyclic graph of some inner type.

    Arguments:
    - `elemType`: `type`

    Accepts an attrset of elements

    The elements should be of type `elemType`
    or sets of the type `{ data, name ? null, before ? [], after ? [] }`
    where the `data` field is of type `elemType`

    `name` defaults to the key in the set.

    Can be used in conjunction with `wlib.dag.topoSort` and `wlib.dag.sortAndUnwrap`

    Note, if the element type is a submodule then the `name` argument
    will always be set to the string "data" since it picks up the
    internal structure of the DAG values. To give access to the
    "actual" attribute name a new submodule argument is provided with
    the name `dagName`.

    The `config.optionname` value from the associated option
    will be normalized such that all items are DAG entries

    If you wish to alter the type, you may provide different options
    to `wlib.dag.dagWith` by updating this type `wlib.types.dagOf // { strict = false; }`
  */

  dagOf = wlib.dag.dagOf;

  /**
    same as `dalOf` except with an extra field `esc-fn`

    esc-fn is to be null, or a function that returns a string

    used by `wlib.modules.makeWrapper`
  */
  dalWithEsc = wlib.types.dalOf // {
    modules = [
      {
        options.esc-fn = lib.mkOption {
          type = lib.types.nullOr (lib.types.functionTo lib.types.str);
          default = null;
        };
      }
    ];
  };

  /**
    same as `dagOf` except with an extra field `esc-fn`

    esc-fn is to be null, or a function that returns a string

    used by `wlib.modules.makeWrapper`
  */
  dagWithEsc = wlib.types.dagOf // {
    inherit (wlib.types.dalWithEsc) modules;
  };

  /**
    Type for a value that can be converted to string `"${like_this}"`

    used by `wlib.modules.makeWrapper`
  */
  stringable = lib.mkOptionType {
    name = "stringable";
    descriptionClass = "noun";
    description = "str|path|drv";
    check = lib.isStringLike;
    merge = lib.mergeEqualOption;
  };

  /**
    Arguments:
    - `length`: `int`,
    - `elemType`: `type`

    It's a list, but it rejects lists of the wrong length.

    Still has regular list merge across multiple definitions, best used inside another list
  */
  fixedList =
    len: elemType:
    let
      base = lib.types.listOf elemType;
    in
    lib.types.addCheck base (x: base.check x && builtins.length x == len)
    // {
      name = "fixedList";
      descriptionClass = "noun";
      description = "(List of length ${toString len})";
    };

  /**
    Arguments:
    - `length`: `int`,

    `len: wlib.types.dalOf (wlib.types.fixedList len wlib.types.stringable)`
  */
  wrapperFlags = len: wlib.types.dalWithEsc (wlib.types.fixedList len wlib.types.stringable);

  /**
    DAL (list) of (stringable or list of stringable)

    More flexible than `wlib.types.wrapperFlags`, allows single items, or lists of items of varied length
  */
  wrapperFlag = wlib.types.dalWithEsc (
    lib.types.oneOf [
      wlib.types.stringable
      (lib.types.listOf wlib.types.stringable)
    ]
  );

  /**
    File type with content and path options

    Arguments:
    - `pkgs`: nixpkgs instance

    Fields:
    - `content`: File contents as string
    - `path`: Derived path using pkgs.writeText
  */
  file =
    # we need to pass pkgs here, because writeText is in pkgs
    pkgs:
    lib.types.submodule (
      { name, config, ... }:
      {
        options = {
          content = lib.mkOption {
            type = lib.types.lines;
            description = ''
              Content of the file. This can be a multi-line string that will be
              written to the Nix store and made available via the path option.
            '';
          };
          path = lib.mkOption {
            type = wlib.types.stringable;
            description = ''
              The path to the file. By default, this is automatically
              generated using pkgs.writeText with the attribute name and content.
            '';
            default = pkgs.writeText name config.content;
            defaultText = "pkgs.writeText name <content>";
          };
        };
      }
    );

  /**
    Like lib.types.anything, but allows contained lists to also be merged
  */
  attrsRecursive = lib.mkOptionType {
    name = "attrsRecursive";
    description = "attrsRecursive";
    descriptionClass = "noun";
    check = value: true;
    merge =
      loc: defs:
      let
        getType =
          value:
          if lib.isAttrs value && lib.isStringLike value then "stringCoercibleSet" else builtins.typeOf value;

        # Returns the common type of all definitions, throws an error if they
        # don't have the same type
        commonType = lib.foldl' (
          type: def:
          if getType def.value == type then
            type
          else
            throw "The option `${lib.showOption loc}' has conflicting option types in ${lib.showFiles (lib.getFiles defs)}"
        ) (getType (lib.head defs).value) defs;

        mergeFunction =
          {
            # Recursively merge attribute sets
            set = (lib.types.attrsOf wlib.types.attrsRecursive).merge;
            # merge lists
            list = (lib.types.listOf wlib.types.attrsRecursive).merge;
            # This is the type of packages, only accept a single definition
            stringCoercibleSet = lib.mergeOneOption;
            lambda =
              loc: defs: arg:
              wlib.types.attrsRecursive.merge (loc ++ [ "<function body>" ]) (
                map (def: {
                  file = def.file;
                  value = def.value arg;
                }) defs
              );
            # Otherwise fall back to only allowing all equal definitions
          }
          .${commonType} or lib.mergeEqualOption;
      in
      mergeFunction loc defs;
  };

  /**
    The kind of type you would provide to `pkgs.lua.withPackages` or `pkgs.python3.withPackages`

    This type is a function from a set of packages to a list of packages.

    If you set it in multiple files, it will merge the resulting lists according to normal module rules for a `listOf package`.
  */
  withPackagesType =
    let
      inherit (lib.types) package listOf functionTo;
    in
    (functionTo (listOf package))
    // {
      merge =
        loc: defs: arg:
        (listOf package).merge (loc ++ [ "<function body>" ]) (
          map (
            def:
            def
            // {
              value = def.value arg;
            }
          ) defs
        );
    };

  /**
    Like `lib.types.submoduleWith` but for wrapper modules!

    Use this when you want your wrapper module to be able to accept other programs along with custom configurations.

    The resulting `config.optionname` value will contain `.config` from the evaluated wrapper module, just like `lib.types.submoduleWith`

    In other words, it will contain the same thing calling `.apply` returns.

    This means you may grab the wrapped package from `config.optionname.wrapper`

    It takes all the same arguments as `lib.types.submoduleWith`, plus 1 extra argument, `mkModuleAfter`

    ```nix
    wlib.types.subWrapperModuleWith {
      modules ? [],
      specialArgs ? {},
      shorthandOnlyDefinesConfig ? false,
      description ? null,
      class ? null,
      mkModuleAfter ? null
    }
    ```

    `mkModuleAfter` may receive a function that gets the full result of evaluating the submodule as an argument.

    If provided, it is to return an extra module to pass to `config.eval` to modify the resulting wrapper module but with access to things like,
    the highest priority override previously declared on the option you want to modify without infinite recursion.
  */
  subWrapperModuleWith =
    {
      modules ? [ ],
      specialArgs ? { },
      shorthandOnlyDefinesConfig ? false,
      description ? null,
      class ? null,
      mkModuleAfter ? null,
    }@attrs:
    let
      # This subWrapperModuleWith function is a modified version of submoduleWith from nixpkgs:
      # https://github.com/NixOS/nixpkgs/blob/91fe5b9c7e2fe8af311aa7cd0adb7d93b2d65bce/lib/types.nix#L1214
      # it uses the wlib.evalModules function, instead of the nixpkgs one.
      checkDefsForError =
        check: loc: defs:
        let
          invalidDefs = builtins.filter (def: !check def.value) defs;
        in
        if invalidDefs != [ ] then
          { message = "Definition values: ${lib.options.showDefs invalidDefs}"; }
        else
          null;

      allModules =
        defs:
        map (
          { value, file }:
          if builtins.isAttrs value && shorthandOnlyDefinesConfig then
            {
              _file = file;
              config = value;
            }
          else
            {
              _file = file;
              imports = [ value ];
            }
        ) defs;

      base = wlib.evalModules {
        inherit class specialArgs;
        modules = [ { _module.args.name = lib.mkOptionDefault "‹name›"; } ] ++ modules;
      };

      freeformType = base._module.freeformType;

      name = "subWrapperModule";

      check = {
        __functor = _self: x: builtins.isAttrs x || lib.isFunction x || lib.types.path.check x;
        isV2MergeCoherent = true;
      };
    in
    lib.mkOptionType {
      inherit name;
      description =
        if description != null then
          description
        else
          let
            docsEval = base.extendModules { modules = [ lib.types.noCheckForDocsModule ]; };
          in
          if docsEval._module.freeformType ? description then
            "open ${name} of ${
              lib.types.optionDescriptionPhrase (
                class: class == "noun" || class == "composite"
              ) docsEval._module.freeformType
            }"
          else
            name;
      inherit check;
      merge = {
        __functor =
          self: loc: defs:
          (self.v2 { inherit loc defs; }).value;
        v2 =
          { loc, defs }:
          let
            res = base.extendModules {
              modules = [ { _module.args.name = lib.last loc; } ] ++ allModules defs;
              prefix = loc;
            };
            configuration = if lib.isFunction mkModuleAfter then res.config.eval (mkModuleAfter res) else res;
          in
          {
            headError = checkDefsForError check loc defs;
            value = configuration.config;
            valueMeta = { inherit configuration; };
          };
      };
      emptyValue = {
        value = { };
      };
      getSubOptions =
        prefix:
        let
          docsEval = base.extendModules {
            inherit prefix;
            modules = [ lib.types.noCheckForDocsModule ];
          };
          # Intentionally shadow the freeformType from the possibly *checked*
          # configuration. See `noCheckForDocsModule` comment.
          inherit (docsEval._module) freeformType;
        in
        docsEval.options
        // lib.optionalAttrs (freeformType != null) {
          # Expose the sub options of the freeform type. Note that the option
          # discovery doesn't care about the attribute name used here, so this
          # is just to avoid conflicts with potential options from the submodule
          _freeformOptions = freeformType.getSubOptions prefix;
        };
      getSubModules = modules;
      substSubModules =
        m:
        wlib.types.subWrapperModuleWith (
          attrs
          // {
            modules = m;
          }
        );
      nestedTypes = lib.optionalAttrs (freeformType != null) {
        freeformType = freeformType;
      };
      functor = lib.defaultFunctor name // {
        type = wlib.types.subWrapperModuleWith;
        payload = {
          inherit
            modules
            class
            specialArgs
            shorthandOnlyDefinesConfig
            description
            mkModuleAfter
            ;
        };
        binOp = lhs: rhs: {
          class =
            # `or null` was added for backwards compatibility only. `class` is
            # always set in the current version of the module system.
            if lhs.class or null == null then
              rhs.class or null
            else if rhs.class or null == null then
              lhs.class or null
            else if lhs.class or null == rhs.class then
              lhs.class or null
            else
              throw "A subWrapperModuleWith option is declared multiple times with conflicting class values \"${toString lhs.class}\" and \"${toString rhs.class}\".";
          modules = lhs.modules ++ rhs.modules;
          specialArgs =
            let
              intersecting = builtins.intersectAttrs lhs.specialArgs rhs.specialArgs;
            in
            if intersecting == { } then
              lhs.specialArgs // rhs.specialArgs
            else
              throw "A subWrapperModuleWith option is declared multiple times with the same specialArgs \"${toString (builtins.attrNames intersecting)}\"";
          shorthandOnlyDefinesConfig =
            if lhs.shorthandOnlyDefinesConfig == null then
              rhs.shorthandOnlyDefinesConfig
            else if rhs.shorthandOnlyDefinesConfig == null then
              lhs.shorthandOnlyDefinesConfig
            else if lhs.shorthandOnlyDefinesConfig == rhs.shorthandOnlyDefinesConfig then
              lhs.shorthandOnlyDefinesConfig
            else
              throw "A subWrapperModuleWith option is declared multiple times with conflicting shorthandOnlyDefinesConfig values";
          description =
            if lhs.description == null then
              rhs.description
            else if rhs.description == null then
              lhs.description
            else if lhs.description == rhs.description then
              lhs.description
            else
              throw "A subWrapperModuleWith option is declared multiple times with conflicting descriptions";
          mkModuleAfter =
            prev:
            let
              a = lhs.mkModuleAfter or null;
              b = rhs.mkModuleAfter or null;
            in
            if a == null && b == null then
              null
            else
              lib.optionals (a != null) (lib.toList (a prev)) ++ lib.optionals (b != null) (lib.toList (b prev));
        };
      };
    };
}
