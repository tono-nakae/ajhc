module MapBinaryInstance() where


import Binary
import Data.FiniteMap
import Data.Map as Map
import Control.Monad

instance (Ord a,Binary a, Binary b) => Binary (Map a b) where
    put_ bh x = do
        put_ bh (Map.size x)
        mapM_ (put_ bh) (Map.toList x) 
    get bh = do
        (sz::Int) <- get bh
        ls <- replicateM sz (get bh)
        return (Map.fromList ls)
        --get bh >>= return . Map.fromList

instance (Ord a,Binary a, Binary b) => Binary (FiniteMap a b) where
   put_ bh x = put_ bh (fmToList x) 
   get bh = get bh >>= return . listToFM
