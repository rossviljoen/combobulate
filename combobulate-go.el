;;; combobulate-go.el --- go support for combobulate  -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Mickey Petersen

;; Author: Mickey Petersen <mickey@masteringemacs.org>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'combobulate-settings)
(require 'combobulate-navigation)
(require 'combobulate-manipulation)
(require 'combobulate-rules)

(defgroup combobulate-go nil
  "Configuration switches for GO"
  :group 'combobulate
  :prefix "combobulate-go-")

(defun combobulate-go-pretty-print-node-name (node default-name)
  "Pretty printer for Go nodes"
  (combobulate-string-truncate
   (replace-regexp-in-string
    (rx (| (>= 2 " ") "\n")) ""
    (pcase (combobulate-node-type node)
      ("function_declaration"
       (concat "func "
               (combobulate-node-text (combobulate-node-child-by-field node "name"))))
      ("type_declaration"
       (concat "type "
               (thread-first node
                             (combobulate-node-child 0)
                             (combobulate-node-child-by-field "name")
                             (combobulate-node-text))))
      ("identifier" (combobulate-node-text node))
      (_ default-name)))
   40))

(defun combobulate-go-setup (_)
  ;; NOTE This is subject to change
  (setq combobulate-envelope-procedure-shorthand-alist
        '((general-statement
           . ((:activation-nodes
               ((:nodes ((rule "block") (rule "_statement")
                         (rule "source_file"))
                        :has-parent ("block" "source_file"))))))))
  (setq combobulate-manipulation-envelopes
        '((:description
           "v, err := ... | if err != nil { ... }"
           :key "E"
           :mark-node t
           :shorthand general-statement
           :name "handle-error"
           :template
           ((p value "Value Variable") ", " (p err "Error Variable") " := " @ r> n>
            "if " (f err) " != nil {" n> @ n> "}" > n>))
          (:description
           "if ... { ... } [else { ... }]"
           :key "i"
           :mark-node t
           :shorthand general-statement
           :name "if-statement"
           :template
           ("if " @ (p true "Condition") " {" n>
            (choice* :missing
                     nil
                     :rest
                     (r> n>)
                     :name "if-block")
            "}" >
            (choice* :missing
                     nil
                     :rest
                     (" else {" n> @ r> n> "}" > n>)
                     :name "else-block")))
          (:description
           "for ... { ... }"
           :key "f"
           :mark-node t
           :shorthand general-statement
           :name "for-loop"
           :template
           ("for "
            (choice*
             :name "Range"
             :rest ("index, value := range " (p variable "Variable")))
            (choice*
             :name "Iterator"
             :rest ((p i "Iterator") " := 0; "
                    (choice* :name "<" :rest ((f i) " < " (p to "Max")))
                    (choice* :name "<=" :rest ((f i) " <= " (p to "Max")))
                    "; "
                    (f i) "++"))
            " {" n> @ r> n> "}" > n>))))
  (setq combobulate-navigation-context-nodes
        '("identifier" "false" "true" "float_literal" "field_identifier" "type_identifier"))
  (setq combobulate-manipulation-indent-after-edit nil)
  (setq combobulate-envelope-indent-region-function #'indent-region)
  (setq combobulate-manipulation-trim-whitespace 'backward)
  (setq combobulate-manipulation-trim-empty-lines t)
  (setq combobulate-manipulation-edit-procedures nil)
  (setq combobulate-pretty-print-node-name-function
        #'combobulate-go-pretty-print-node-name)
  (setq combobulate-navigation-sibling-skip-prefix t)
  (setq combobulate-navigation-sexp-procedures nil)
  (setq combobulate-manipulation-plausible-separators '(";" "," "\n"))
  (setq combobulate-navigation-defun-procedures
        '((:activation-nodes ((:nodes ("function_declaration"))))))
  (setq combobulate-navigation-logical-procedures
        '((:activation-nodes ((:nodes (all))))))
  (setq combobulate-navigation-sibling-procedures
        `((:activation-nodes
           ((:nodes
             ((rule "literal_value")
              (rule "for_clause"))
             :has-parent ("literal_value" "for_clause")))
           :selector (:choose
                      parent
                      :match-children
                      (:discard-rules ("literal_value"))))
          ;; This is intended to match the two types of switch
          ;; statement but only the actual case clauses and not the
          ;; identifier alias clause itself.
          (:activation-nodes
           ((:nodes (rule-rx ("switch_statement" eol))
                    :position at
                    :has-parent (rx ("switch_statement" eol))))
           :selector (:choose parent :match-children (:match-rules (rx ("case" eol)))))
          (:activation-nodes
           ((:nodes (rule "_statement")
                    :has-parent (rx ("case" eol))))
           :selector (:choose parent :match-children t))
          ;; -- End switch
          (:activation-nodes
           ((:nodes ((rule "block") (rule "source_file"))
                    :position at
                    :has-parent ("block" "source_file")))
           :selector (:choose parent :match-children t))
          ;; lists with declarations as immediate childre
          (:activation-nodes
           ((:nodes ((rx ("declaration_list" eol)))))
           :selector (:choose
                      node
                      :match-children
                      (:match-rules (rx ("_declaration" eol)))))
          (:activation-nodes
           ((:nodes ((rule "argument_list"))
                    :has-parent ("argument_list"))
            (:nodes ((rule "expression_list"))
                    :has-parent "expression_list"))
           :selector (:choose
                      parent
                      :match-children t))
          (:activation-nodes
           ((:nodes ("import_spec_list")))
           :selector (:choose
                      node
                      :match-children t))
          (:activation-nodes
           ((:nodes  (rule "_statement")
                     :has-parent ((rule "_statement"))))
           :selector (:choose
                      parent
                      :match-children t))
          (:activation-nodes
           ((:nodes  (rx ("_declaration" eol))))
           :selector (:choose
                      node
                      :match-children t))
          (:activation-nodes
           ((:nodes ((rx ("statement" eol)))))
           :selector (:choose
                      node
                      :match-children t))))
  (setq combobulate-navigation-parent-child-procedures
        `((:activation-nodes
           ((:nodes "block" :position at))
           :selector (:choose node :match-children t))
          (:activation-nodes
           ((:nodes "expression_case" at))
           :selector (:choose node :match-children t))
          (:activation-nodes
           ((:nodes ((rule "_statement")
                     (rule "_simple_statement")
                     (rule "source_file"))
                    :position at))
           :selector (:choose node :match-children
                              (:match-rules ("block"))))
          (:activation-nodes
           ((:nodes ((all))))
           :selector (:choose node :match-children t)))))

(provide 'combobulate-go)
;;; combobulate-go.el ends here
