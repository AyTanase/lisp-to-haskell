(in-package :hs)


(defvar *indent* 0
  "the current indentation level")

(defun indent (&optional (n *indent*))
  (fresh-line)
  (loop repeat n
    do (write-string "  ")))

(defmacro with-indent (n &body body)
  `(let ((*indent* (+ *indent* ,n)))
     ,@body))

(defun map-indent (fn xs &optional (n *indent*))
  (dolist (x xs)
    (indent n)
    (apply fn x)))


(defun %type (vars type)
  (arrange vars)
  (haskell-tops " :: " type))

(defkeyword |type| (vars type)
  `(%type ',vars ',type))

(defapply apply-syntax |type| #'%type)


(defun tuple (xs)
  (with-paren
    (arrange xs)))

(defpattern |tuple| (&rest xs)
  (tuple xs))


(declaim (ftype function %define reduce-guard-1))

(defun truep (x)
  (case x (#!(True otherwise) t)))

(defun merge-guards (x y)
  (cond
    ((truep x) y)
    ((truep y) x)
    (t `(|and| ,x ,y))))

(defun %where (defs)
  (if defs
    (with-indent 1
      (indent)
      (write-string "where")
      (with-indent 1
        (map-indent #'%define defs)))))

(defun %print-guard-1 (expr)
  (if (callp expr '|and|)
    (%rechask (cdr expr) #'%print-guard-1 ", ")
    (haskell expr)))

(defun %print-guards (assign gvs defs)
  (flet ((print-1 (g v)
           (write-string "| ")
           (%print-guard-1 g)
           (haskell-tops assign v)))
    (with-indent 1
      (map-indent #'print-1 gvs))
    (%where defs)))

(defun reduce-guard-if (f guard expr)
  (ds-bind (x y &optional (z nil svar)) (cdr expr)
    (let ((vg (if svar (funcall f guard) guard)))
      (nconc (reduce-guard-1 f (merge-guards vg x) y)
             (if svar (reduce-guard-1 f vg z))))))

(defun reduce-guard-if-bind (f guard expr)
  (ds-bind (x y &optional (z nil svar)) (cdr expr)
    (let ((w `(|setf| ,@x))
          (vg (if svar (funcall f guard) guard)))
      (cons (list (merge-guards vg w) y)
            (if svar (reduce-guard-1 f vg z))))))

(defun reduce-guard-1 (f guard value)
  (let ((expr (hs-macro-expand value)))
    (flet ((base () (list (list guard expr))))
      (cond
        ((atom expr) (base))
        ((eq (car expr) '|if|)
          (reduce-guard-if f guard expr))
        ((eq (car expr) '|if-bind|)
          (reduce-guard-if-bind f guard expr))
        (t (base))))))

(defun reduce-guards (assign defs expr)
  (let ((gs nil))
    (flet ((gpush (guard)
             (if (atom guard)
               guard
               (let ((v (genvar)))
                 (push (list v guard) gs)
                 v))))
      (let ((gvs (reduce-guard-1 #'gpush '|otherwise| expr)))
        (%print-guards assign gvs (append defs (nreverse gs)))))))

(defun %define-guard (assign defs expr)
  (if (callp expr '|if|)
    (reduce-guards assign defs expr)
    (progn
      (haskell-tops assign expr)
      (%where defs))))

(defun %define-right (assign value)
  (let ((expr (hs-macro-expand value)))
    (if (callp expr '|where|)
      (%define-guard assign (second expr)
                     (hs-macro-expand (third expr)))
      (%define-guard assign nil expr))))

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

(defsyntax #!(let where) (defs val)
  (if defs
    (%let defs val)
    (haskell-top val)))

(def-sexp-rule #!(let where) (defs val)
  (if defs
    (with-paren
      (%let defs val))
    (haskell val)))


(defun =>-left (args)
  (when (consp args)
    (if (and (consp (car args))
             (consp (cdr args)))
      (tuple args)
      (haskell-top args))
    (write-string " => ")))

(defsyntax => (args type)
  (=>-left args)
  (haskell-top type))


(defun %class-derive (args)
  (if (consp args)
    (ds-bind (key &rest rest) args
      (if (symbolp key)
        (progn
          (format t "{-# ~@:(~a~) #-} " key)
          (if rest
            (=>-left rest)))
        (=>-left args)))))

(defun %class (key name derive defs)
  (format t "~a " key)
  (%class-derive derive)
  (haskell-top name)
  (when defs
    (write-string " where")
    (with-indent 1
      (map-indent #'%define defs))))

(defmacro def-class-macro (key)
  `(defkeyword ,key (name &optional derive &rest defs)
     `(%class ',',key ',name ',derive ',defs)))

(def-class-macro |class|)
(def-class-macro |instance|)


(defun module-names (svar names)
  (when svar
    (write-string " ")
    (if (callp names :|hide|)
      (progn
        (write-string "hiding ")
        (tuple (cdr names)))
      (tuple names))))

(defun %defmodule (module svar names)
  (haskell-tops "module " module)
  (module-names svar names)
  (write-string " where"))

(defkeyword |defmodule| (module &optional (names nil svar))
  `(%defmodule ',module ,svar ',names))

(defun %import (module svar names)
  (haskell-tops "import " module)
  (module-names svar names))

(defkeyword |import| (module &optional (names nil svar))
  `(%import ',module ,svar ',names))

(defhasq :|m| "module")
(defhasq :|q| "qualified")
(defhasq :|all| "(..)")


(defkeyword |deftype| (name type)
  `(haskell-tops "type " ',name " = " ',type))


(defun %data-body (body)
  (if (and (consp body)
           (callp (cdr body) :|name|))
    (progn
      (haskell-tops (car body) " { ")
      (%rechask (cddr body) (curry #'apply #'%type) ", ")
      (write-string " }"))
    (haskell-top body)))

(defun %data (key name body deriving)
  (format t "~a " key)
  (haskell-tops name " = ")
  (if (callp body '|or|)
    (%rechask (cdr body) #'%data-body " | ")
    (%data-body body))
  (when deriving
    (write-string " deriving ")
    (tuple deriving)))

(defmacro def-data-macro (key)
  `(defkeyword ,key (name constr &optional deriving)
     `(%data ',',key ',name ',constr ',deriving)))

(def-data-macro |data|)
(def-data-macro |newtype|)


(defsyntax |if| (x y &optional (z nil svar))
  (cond
    ((not svar)
      (assert (truep x) () "if: missing else-form")
      (haskell-top y))
    ((and (atom x) (atom y) (atom z))
      (haskells "if " x " then " y " else " z))
    (t (with-indent 1
         (haskell-tops "if " x)
         (indent)
         (haskell-tops "then " y)
         (indent)
         (haskell-tops "else " z)))))

(def-syntax-macro |cond| (x &body xs)
  `(|if| ,@x ,@(if xs `((|cond| ,@xs)))))


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
;; eval: (add-cl-indent-rule (quote ds-bind) (quote (&lambda 4 &body)))
;; End:
