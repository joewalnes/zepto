; Clojure sample file demonstrating syntax features
; This also demonstrates common Lisp/Scheme patterns

(ns myapp.core
  "Namespace documentation string"
  (:require [clojure.string :as str]
            [clojure.set :refer [union intersection]]
            [clojure.java.io :as io])
  (:import [java.util Date UUID]
           [java.io File]))

;; Constants and definitions
(def MAX-SIZE 100)
(def ^:const PI 3.14159)
(def ^:private private-val "secret")
(def ^:dynamic *debug* false)

;; Basic data types
(def my-string "Hello, World!")
(def my-number 42)
(def my-float 3.14)
(def my-ratio 1/3)
(def my-boolean true)
(def my-nil nil)
(def my-keyword :keyword)
(def my-namespaced-keyword ::namespaced)
(def my-symbol 'symbol)

;; Collections
(def my-list '(1 2 3 4 5))
(def my-vector [1 2 3 4 5])
(def my-set #{1 2 3 4 5})
(def my-map {:name "Alice" :age 30})

;; Nested collections
(def nested-map {:user {:name "Bob"
                        :address {:city "NYC"
                                  :zip "10001"}}})

;; Regular expression
(def email-pattern #"[\w.]+@[\w.]+\.\w+")

;; Anonymous function shorthand
(def double-it #(* % 2))
(def add-them #(+ %1 %2))

;; Function definition
(defn greet
  "Greets a person by name"
  [name]
  (str "Hello, " name "!"))

;; Multi-arity function
(defn greet-all
  "Greets one or more people"
  ([] "Hello!")
  ([name] (str "Hello, " name "!"))
  ([name & others]
   (str "Hello, " name " and " (str/join ", " others) "!")))

;; Private function
(defn- helper-fn
  [x]
  (* x x))

;; Higher-order function
(defn apply-twice
  "Applies f to x twice"
  [f x]
  (f (f x)))

;; Function with destructuring
(defn process-person
  [{:keys [name age] :as person}]
  (println "Name:" name "Age:" age)
  person)

;; Let binding
(defn calculate
  [x y]
  (let [sum (+ x y)
        diff (- x y)
        product (* x y)]
    {:sum sum :diff diff :product product}))

;; Conditionals
(defn classify-number
  [n]
  (cond
    (neg? n) :negative
    (zero? n) :zero
    (pos? n) :positive
    :else :unknown))

(defn abs-value
  [n]
  (if (neg? n)
    (- n)
    n))

;; Case expression
(defn day-type
  [day]
  (case day
    (:saturday :sunday) :weekend
    (:monday :tuesday :wednesday :thursday :friday) :weekday
    :unknown))

;; When and when-not
(defn maybe-print
  [condition msg]
  (when condition
    (println msg)
    true))

;; Threading macros
(defn process-data
  [data]
  (-> data
      (str/trim)
      (str/lower-case)
      (str/split #"\s+")
      (first)))

(defn transform-numbers
  [numbers]
  (->> numbers
       (filter even?)
       (map #(* % 2))
       (reduce +)))

;; Loop/recur
(defn factorial
  [n]
  (loop [i n
         acc 1]
    (if (<= i 1)
      acc
      (recur (dec i) (* acc i)))))

;; Lazy sequences
(defn fibonacci
  []
  (letfn [(fib [a b]
            (lazy-seq (cons a (fib b (+ a b)))))]
    (fib 0 1)))

;; Destructuring
(defn vector-destruct
  [[first second & rest :as all]]
  {:first first :second second :rest rest :all all})

(defn map-destruct
  [{:keys [a b] :or {a 0 b 0} :as m}]
  (+ a b))

;; Protocols
(defprotocol Greeter
  "Protocol for greeting"
  (say-hello [this])
  (say-goodbye [this]))

;; Records
(defrecord Person [name age]
  Greeter
  (say-hello [this]
    (str "Hello, I'm " name))
  (say-goodbye [this]
    (str "Goodbye from " name)))

;; Multimethods
(defmulti area :shape)

(defmethod area :circle
  [{:keys [radius]}]
  (* PI radius radius))

(defmethod area :rectangle
  [{:keys [width height]}]
  (* width height))

(defmethod area :default
  [_]
  0)

;; Atoms (mutable state)
(def counter (atom 0))

(defn increment-counter!
  []
  (swap! counter inc))

(defn reset-counter!
  []
  (reset! counter 0))

;; Try/catch
(defn safe-parse
  [s]
  (try
    (Integer/parseInt s)
    (catch NumberFormatException e
      (println "Parse error:" (.getMessage e))
      nil)
    (finally
      (println "Parsing attempted"))))

;; Macros
(defmacro unless
  "Inverse of if"
  [condition & body]
  `(if (not ~condition)
     (do ~@body)))

(defmacro with-timing
  "Measures execution time"
  [& body]
  `(let [start# (System/currentTimeMillis)
         result# (do ~@body)
         end# (System/currentTimeMillis)]
     (println "Elapsed:" (- end# start#) "ms")
     result#))

;; Java interop
(defn java-interop-examples
  []
  (let [date (Date.)              ; Constructor
        uuid (UUID/randomUUID)     ; Static method
        upper (.toUpperCase "hello")] ; Instance method
    {:date date :uuid uuid :upper upper}))

;; Anonymous functions
(def add-fn (fn [a b] (+ a b)))
(def short-fn #(+ %1 %2))

;; Special characters in symbols
(def valid-symbol? true)
(def +plus+ 10)
(def *star* 20)

;; Comment forms
(comment
  (println "This won't execute")
  (+ 1 2 3))

#_(println "This is also a comment")

;; Main function
(defn -main
  "Main entry point"
  [& args]
  (println (greet "World"))
  (println (transform-numbers (range 10)))
  (let [p (->Person "Alice" 30)]
    (println (say-hello p))))
