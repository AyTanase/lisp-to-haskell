(in-package :hs)


(defvar *indent* 0)

(defun indent (&optional (n *indent*))
  (fresh-line)
  (loop repeat n
    do (write-string "  ")))

(defmacro with-indent (n &body body)
  `(let ((*indent* (+ *indent* ,n)))
     ,@body))

(defun map-indent (fn list &optional (n *indent*))
  (dolist (x list)
    (indent n)
    (apply fn x)))


(defun %type (vars type)
  (arrange vars)
  (haskell-tops " :: " type))

(defkeyword |type| (vars type)
  `(%type ',vars ',type))

(defsyntax |type| (var type)
  (%type (list var) type))


(defun tuple (xs)
  (with-paren
    (arrange xs)))

(defpattern |tuple| (&rest xs)
  (tuple xs))


(declaim (ftype function %define reduce-cond-1))

(defun %if->cond (sexp)
  (destructuring-bind (x y &optional (z nil svar)) sexp
    `((,x ,y) ,@(if svar `((|otherwise| ,z))))))

(defun if->cond (expr)
  (if (and (consp expr)
           (eq (car expr) '|if|))
    `(|cond| ,@(%if->cond (cdr expr)))
    expr))

(defun truep (x)
  (case x ((|True| |otherwise|) t)))

(defun merge-guards (x y)
  (cond
    ((truep x) y)
    ((truep y) x)
    (t `(|and| ,x ,y))))

(defun reduce-cond-cond (f guard expr)
  (let ((var (funcall f guard (cdr expr))))
    (loop for (g v) in (cdr expr)
      nconc (reduce-cond-1 f (merge-guards var g) v))))

(defun reduce-cond-if-bind (f guard expr)
  (let* ((gvs (%if->cond `((|setf| ,@(cadr expr))
                           ,@(cddr expr))))
         (var (funcall f guard gvs)))
    (loop for (g v) in gvs
      collect (list (merge-guards var g) v))))

(defun reduce-cond-1 (f guard value)
  (let ((expr (if->cond value)))
    (if (consp expr)
      (case (car expr)
        (|cond|
          (reduce-cond-cond f guard expr))
        (|if-bind|
          (reduce-cond-if-bind f guard expr))
        (t (list (list guard expr))))
      (list (list guard expr)))))

(defun reduce-cond (value)
  (let ((guards nil))
    (flet ((gpush (guard gvs)
             (if (or (truep guard)
                     (null (cdr gvs)))
               guard
               (let ((var (genvar)))
                 (push (list var guard) guards)
                 var))))
      (let ((expr (mapcan (curry #'apply #'reduce-cond-1 #'gpush)
                          (cdr value))))
        (values expr (nreverse guards))))))

(defun %where (defs)
  (if defs
    (with-indent 1
      (indent)
      (write-string "where")
      (with-indent 1
        (map-indent #'%define defs)))))

(defun %cond (assign defs expr)
  (labels ((print-guard (g)
             (if (and (consp g)
                      (eq (car g) '|and|))
               (%rechask (cdr g) #'print-guard ", ")
               (haskell g)))
           (print-def (g v)
             (write-string "| ")
             (print-guard g)
             (haskell-tops assign v)))
    (multiple-value-bind (exps gs) (reduce-cond expr)
      (with-indent 1
        (map-indent #'print-def exps))
      (%where (append defs gs)))))

(defun %define-guard (assign defs value)
  (let ((expr (if->cond value)))
    (if (and (consp expr)
             (eq (car expr) '|cond|))
      (%cond assign defs expr)
      (progn
        (haskell-tops assign expr)
        (%where defs)))))

(defun %define-right (assign value)
  (cond
    ((atom value)
      (haskell-tops assign value))
    ((eq (car value) '|cond|)
      (%cond assign nil value))
    (t (let ((expanded (hs-macro-expand value)))
         (if (eq (first expanded) '|where|)
           (%define-guard assign (second expanded) (third expanded))
           (%define-guard assign nil expanded))))))

(defun %define (var val &optional (assign " = "))
  (if (eq var '|type|)
    (%type val assign)
    (progn
      (haskell-top var)
      (%define-right assign val))))

(defkeyword |define| (var val)
  `(%define ',var ',val))


(defun %let (defs val)
  (write-string "let")
  (with-indent 1
    (map-indent #'%define defs)
    (indent)
    (haskell-tops "in " val)))

(defsyntax |let| (defs val)
  (if defs
    (%let defs val)
    (haskell-top val)))

(def-sexp-rule |let| (defs val)
  (if defs
    (with-paren
      (%let defs val))
    (haskell val)))


(shadow-haskell '|where|)

(setf (gethash '|where| *syntax*)
      (gethash '|let| *syntax*))

(setf (gethash '|where| *sexp-rules*)
      (gethash '|let| *sexp-rules*))


(defun %class-derive (derive)
  (when (consp derive)
    (if (symbolp (car derive))
      (progn
        (format t "{-# ~@:(~a~) #-} " (car derive))
        (tuple (cdr derive)))
      (tuple derive))
    (write-string " => ")))

(defun %class (key name derive defs)
  (format t "~a " key)
  (%class-derive derive)
  (haskell-top name)
  (when defs
    (write-string " where")
    (with-indent 1
      (map-indent #'%define defs))))

(defkeyword |class| (name &optional derive &rest defs)
  `(%class '|class| ',name ',derive ',defs))

(defkeyword |instance| (name &optional derive &rest defs)
  `(%class '|instance| ',name ',derive ',defs))

(defkeyword |defdata| (name &rest defs)
  `(%class '|data| ',name nil ',defs))


(defun module-names (svar names)
  (when svar
    (write-string " ")
    (tuple names)))

(defun %defmodule (module svar names)
  (format t "module ~a" module)
  (module-names svar names)
  (write-string " where"))

(defkeyword |defmodule| (module &optional (names nil svar))
  `(%defmodule ',module ,svar ',names))

(defun %import (qualify? module hide? svar names)
  (write-string "import ")
  (if qualify?
    (write-string "qualified "))
  (princ module)
  (if hide?
    (write-string " hiding"))
  (module-names svar names))

(defmacro defimport (name qualify?)
  `(defkeyword ,name (module &optional (names nil svar) hide?)
     `(%import ',',qualify? ',module ',hide? ,svar ',names)))

(defimport |import| nil)
(defimport |require| t)

(defhasq :|all| "(..)")


(defsyntax => (constraints type)
  (if (consp (car constraints))
    (tuple constraints)
    (haskell-top constraints))
  (haskell-tops " => " type))


(defkeyword |deftype| (name type)
  `(haskell-tops "type " ',name " = " ',type))


(defun %data-body (body)
  (if (and (consp body)
           (consp (cdr body))
           (eq (cadr body) :|name|))
    (progn
      (haskell-tops (car body) " { ")
      (%rechask (cddr body) (curry #'apply #'%type) ", ")
      (write-string " }"))
    (haskell-top body)))

(defun %data (name body deriving)
  (haskell-tops "data " name " = ")
  (if (and (consp body)
           (eq (car body) '|or|))
    (%rechask (cdr body) #'%data-body " | ")
    (%data-body body))
  (when deriving
    (write-string " deriving ")
    (tuple deriving)))

(defkeyword |data| (name body &optional deriving)
  `(%data ',name ',body ',deriving))


(defsyntax |if| (x y z)
  (with-indent 1
    (haskell-tops "if " x)
    (indent)
    (haskell-tops "then " y)
    (indent)
    (haskell-tops "else " z)))

(def-sexp-rule |if| (x y z)
  (with-paren
    (haskells "if " x " then " y " else " z)))

(def-syntax-macro |cond| (x &rest xs)
  (if xs
    `(|if| ,@x (|cond| ,@xs))
    (progn
      (assert (truep (first x)))
      (second x))))


(defsyntax |case| (x &rest xs)
  (flet ((case-val (x y)
           (%define x y " -> ")))
    (haskells "case " x " of")
    (with-indent 1
      (map-indent #'case-val xs))))


(defpattern |setf| (x y)
  (haskell-tops x " <- " y))

(defsyntax |do| (&rest body)
  (write-string "do")
  (with-indent 1
    (dolist (expr body)
      (indent)
      (haskell-top expr))))


(defsyntax |lambda| (args expr)
  (write-char #\\)
  (rechask args)
  (haskell-tops " -> " expr))

(defkeyword |extension| (&rest args)
  `(format t "{-# LANGUAGE ~{~a~^, ~} #-}" ',args))

(defhasq :|as| "@")

(def-hs-macro |defconstant| (name expr)
  `(defhasq ,name ,(strhask expr)))

;; Local Variables:
;; eval: (cl-indent-rules (quote (&body)) (quote with-paren) (quote with-pragma))
;; End:
