module Stats(Stats,new,tick,ticks,getTicks,Stats.print,clear,MonadStats(..),combine, printStat, Stat, mtick, mticks, runStatT, runStatIO, tickStat, StatT, theStats ) where


import qualified Data.HashTable as H
import Atom
import GenUtil
import List(sort,groupBy)
import CharIO
import Data.Tree
import qualified Doc.Chars as C
import Char
import Data.IORef
import Control.Exception
import Control.Monad.Trans
import Control.Monad.Writer
import Control.Monad.Reader
import Control.Monad.Identity
import Control.Monad.Fix
import System.IO.Unsafe
import qualified Data.Map as Map


data Stats = Stats !(IORef Int) !(H.HashTable Atom Int)

    
                    
{-# NOINLINE theStats #-}
theStats :: Stats
theStats = unsafePerformIO new



combine :: Stats -> Stats -> IO ()
combine stats (Stats _ h2) = do
    --c <- readIORef c2
    --modifyIORef c1 (+ c)
    ls <- H.toList h2
    let f (a,i) = ticks stats i a
    mapM_ f ls 
    

new = do
    h <- H.new (==) (fromIntegral . atomIndex) 
    r <- newIORef 0
    return $ Stats r h

clear (Stats r h) = do
    writeIORef r 0
    xs <- H.toList h 
    mapM_ (H.delete h) (fsts xs)

toList (Stats _ h) = H.toList h

getTicks (Stats r _)  = readIORef r 

tick stats k = ticks stats 1 k


ticks _ 0 _ = return ()
ticks (Stats r h) c k' = do
    let k = toAtom k'
    liftIO $ modifyIORef r (+ c)
    liftIO $ readIORef r >>= evaluate
    v <- liftIO $ H.lookup h k
    case v of
        Just n -> liftIO $ H.delete h k >> (H.insert h k $! (n + c))
        Nothing -> liftIO $ H.insert h k c

splitUp str = filter (not . null) (f str)  where
    f str = case span (`notElem` ".{") str  of
     (x,"") -> [x]
     (x,('.':rs)) -> x:f rs
     (x,('{':rs)) -> case span (/= '}') rs of
            (a,'}':b) -> x:a:f b
            (a,"") -> [x,a]


print greets stats = do
    l <- toList stats
    --let fs = createForest 0 $ sort [(split (== '.') $ fromAtom x,y) | (x,y) <- l]
    let fs = createForest 0 $ sort [(splitUp $ fromAtom x,y) | (x,y) <- l]
    --CharIO.putErrLn greets
    mapM_ CharIO.putErrLn $ ( draw . fmap p ) (Node (greets,0) fs)  where
        p (x,0) = x
        p (x,n) = x ++ ": " ++ show n

createForest :: a -> [([String],a)] -> Forest (String,a)
createForest def xs = map f gs where
    --[Node (concat $ intersperse "." (xs),y) [] | (xs,y) <- xs] 
    f [(xs,ys)] =  Node (concatInter "." xs,ys) []
    f xs@((x:_,_):_) = Node (x,def) (createForest def [ (xs,ys) | (_:xs@(_:_),ys)<- xs])
    f _ = error "createForest: should not happen."
    gs = groupBy (\(x:_,_) (y:_,_) -> x == y) xs
--createForest  xs = Node ("","") [ createTree [(xs,y)] | (xs,y) <- xs]

draw :: Tree String -> [String]
draw (Node x ts0) = x : drawSubTrees ts0
  where drawSubTrees [] = []
        drawSubTrees [t] =
                {-[vLine] :-} shift [chr 0x2570, chr 0x2574] "  " (draw t)
        drawSubTrees (t:ts) =
                {-[vLine] :-} shift (C.lTee ++ [chr 0x2574]) (C.vLine  ++ " ") (draw t) ++ drawSubTrees ts

        shift first other = zipWith (++) (first : repeat other)
        --vLine = chr 0x254F
        
tickStat ::  Stats -> Stat -> IO ()
tickStat stats (Stat stat) = sequence_  [ ticks stats n a | (a,n) <- Map.toList stat]

runStatIO :: MonadIO m =>  Stats -> StatT m a -> m a 
runStatIO stats action = do
    (a,s) <- runStatT action
    liftIO $ tickStat stats s
    return a

instance MonadStats IO where 
    mticks' n a = ticks theStats n a

-- Pure varients
        
newtype Stat = Stat (Map.Map Atom Int)
    
printStat greets (Stat s) = do
    let fs = createForest 0 $ sort [(splitUp $ fromAtom x,y) | (x,y) <- Map.toList s]
    mapM_ CharIO.putErrLn $ ( draw . fmap p ) (Node (greets,0) fs)  where
        p (x,0) = x
        p (x,n) = x ++ ": " ++ show n

{-
instance DocLike d => PPrint d Stat where 
    pprint (Stat s) =  ( draw . fmap p ) (Node (greets,0) fs)  where
        fs = createForest 0 $ sort [(splitUp $ fromAtom x,y) | (x,y) <- Map.toList s]
        p (x,0) = x
        p (x,n) = x ++ ": " ++ show n
-}

instance Monoid Stat where
    mempty = Stat Map.empty
    mappend (Stat a) (Stat b) = Stat $ Map.unionWith (+) a b
    --mconcat xs = Stat $ Map.unionsWith (+) [ x | Stat x <- xs]
    
    
newtype StatT m a = StatT (WriterT Stat m a)
    deriving(MonadIO, Functor, MonadFix, MonadTrans, Monad)
    
runStatT (StatT m) =  runWriterT m 

class Monad m => MonadStats m where
    mticks' ::  Int -> Atom -> m ()

-- These are inlined so the 'toAtom' can become a caf and be shared 
{-# INLINE mtick  #-}
{-# INLINE mticks #-}
mtick k = mticks' 1 (toAtom k)
mticks n k = n `seq` mticks' n (toAtom k)

--instance (Monad m, Monad (t m), MonadTrans t, MonadReader r m) => MonadReader r (t m) where
--    ask = lift $ ask 
  --  (r -> r) ->  m a -> t m a
  --  (r -> r) -> m a -> m a
  --  local l m = local l m
  --  mticks' n k = lift $ mticks' n k

instance MonadStats Identity where
    mticks' _ _ = return ()

instance MonadReader r m => MonadReader r (StatT m) where 
    ask = lift $ ask
    local f (StatT m) = StatT $ local f m
    
instance (Monad m, Monad (t m), MonadTrans t, MonadStats m) => MonadStats (t m) where
    mticks' n k = lift $ mticks' n k
    
instance Monad m => MonadStats (StatT m) where
    mticks' n k = StatT $ tell (Stat $ Map.singleton k n)


