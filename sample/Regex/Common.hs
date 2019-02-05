module Common where

data Op = Finite | Compare Char Op | Split Op Op

instance Show Op where
  show = const "#<REGEX.OP>"

type NFA = Op -> Op

type BinOp a = a -> a -> a

split :: BinOp NFA
split f g x = Split (f x) (g x)

safeTail :: [a] -> Maybe [a]
safeTail [] = Nothing
safeTail xs = Just (tail xs)
