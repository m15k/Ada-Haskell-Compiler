module Facade (module Inner, twice) where

import Inner

twice :: Widget -> Widget
twice w = spin (spin w)
