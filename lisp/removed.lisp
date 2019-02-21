(in-package :hs)

(defspecial |curry| (&rest args)
  (rechask args))

(defrechask rec%hask #'%haskell " ")

(defsynonym |setf| |bind|)

(def-syntax-macro |if-bind| (args &rest rest)
  `(|if| (|bind| ,@args) ,@rest))
