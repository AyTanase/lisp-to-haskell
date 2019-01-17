module Exec where
import Common
import Control.Applicative
matchHead :: Num a => (NFA -> [Char] -> (Maybe a))
matchHead = (matchHead' 0) where
  matchHead' n Finite _ = (Just n)
  matchHead' n (Compare x rx) (y:ys)
    | (x == y) = (matchHead' (n + 1) rx ys)
  matchHead' _ (Compare _ _) _ = Nothing
  matchHead' n (Split p q) xs = ((matchHead' n p xs) <|> (matchHead' n q xs))
match :: Num a => (NFA -> [Char] -> (Maybe (a, a)))
match = (match' 0) where
  match' n rx xs = ((fmap ((,) n) (matchHead rx xs)) <|> (if (null xs) then Nothing else (match' (n + 1) rx (tail xs))))
