# ColorTools Color Picker

## [1.9.0](https://github.com/muhmiauwauWOW/ColorTools/tree/1.9.0) (2025-07-27)
[Full Changelog](https://github.com/muhmiauwauWOW/ColorTools/compare/1.8.6...1.9.0) [Previous Releases](https://github.com/muhmiauwauWOW/ColorTools/releases)

- Update README and toc formatting  
    Improved README with clearer feature list, added notes section, and corrected minor formatting. Updated ColorTools.toc to comment out test.lua for better clarity.  
- Refactor palette creation functions for clarity  
    Palette creation functions have been refactored for improved readability and maintainability. Each palette creator is now a dedicated function, replacing generic table-driven logic. Sorting and filtering logic has been made explicit, and table.sort is used for consistent ordering. This change makes it easier to add or modify palette types and improves code clarity.  
- Refactor palette creation to use lodash methods  
    Replaced manual table iteration and sorting with lodash-style \_.map, \_.sortBy, and \_.filter for palette creation functions. This improves code readability and consistency across color palette generation.  
- Refactor loops to use \_.forEach for iteration  
    Replaced all Lua 'pairs' and 'ipairs' loops with calls to \_.forEach for more consistent and readable iteration across ColorConnector.lua and mixins.lua. This change improves code maintainability and leverages the utility library for collection processing.  
- Add esMX locale and improve color palette filtering  
    Added Spanish (Mexico) localization file. Updated covenant colors palette creation to filter and validate color entries. Improved sorting in ColorToolsPaletteMixin to handle non-numeric sort values safely.  
- Add localization files for multiple languages  
    Added new localization files for deDE, esES, frFR, itIT, koKR, ptBR, ruRU, zhCN, and zhTW. Updated locale.xml to include these new language files for ColorTools.  
- Refactor color palette creation logic  
    Modularized color palette creation by introducing ColorUtils and PaletteCreators tables. Improved code reuse, readability, and maintainability by consolidating color processing and palette registration logic. Added sorting and validation utilities for color tables and standardized palette initialization.  
- Refactor palette order assignment logic  
    Removed hardcoded 'order' fields from palette creation functions and now assign palette order dynamically during initialization. This simplifies palette definitions and centralizes order management.  
- Refactor and expand color palette creation  
    Reorganized ColorConnector.lua to use modular palette creation functions for various color sources, improving maintainability and extensibility. Added new palettes for font colors, covenant colors, material text colors, player faction colors, and material title text colors. Updated enUS locale with new color names and palette labels for better UI clarity.  
- Refactor color unpacking and palette updates  
    Replaced deprecated 'table.unpack' with 'unpack' for color arrays and updated palette update calls to remove unused arguments. Also refactored table iteration from 'table.foreach' to 'pairs' for better performance and compatibility. Updated .toc file to support additional interface versions and fixed test.lua file inclusion.  
