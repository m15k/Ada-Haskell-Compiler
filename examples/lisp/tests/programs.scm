; recursion through the global environment
(define (fact n)
  (if (= n 0) 1 (* n (fact (- n 1)))))
(fact 25)

; mutual recursion at top level
(define (even? n) (if (= n 0) #t (odd? (- n 1))))
(define (odd? n) (if (= n 0) #f (even? (- n 1))))
(even? 100)
(odd? 7)

; higher-order functions from the boot prelude
(map (lambda (x) (* x x)) (range 1 11))
(filter (lambda (x) (= (remainder x 3) 0)) (range 1 20))
(fold-left + 0 (range 1 101))
(fold-right cons '() '(1 2 3))
(sum (map (lambda (x) (* x x)) (range 1 11)))
(assoc 'b '((a 1) (b 2) (c 3)))
(member 3 '(1 2 3 4))
(apply + '(1 2 3 4))

; closures capture their environment
(define (make-adder n) (lambda (x) (+ x n)))
(define add5 (make-adder 5))
(add5 37)

; letrec ties the knot with laziness
(letrec ((fib (lambda (n)
                (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))))
  (fib 20))

; exact rational arithmetic: harmonic sum stays exact
(define (harmonic n)
  (if (= n 0) 0 (+ (/ 1 n) (harmonic (- n 1)))))
(harmonic 10)

; bignums via expt and fact
(define (choose n k)
  (/ (fact n) (* (fact k) (fact (- n k)))))
(choose 52 5)
(expt 3 50)

; a tiny symbolic differentiator: (d expr x) over +, *, constants
(define (const? e x) (or (number? e) (and (symbol? e) (not (eq? e x)))))
(define (d e x)
  (cond ((number? e) 0)
        ((symbol? e) (if (eq? e x) 1 0))
        ((eq? (car e) '+) (list '+ (d (cadr e) x) (d (caddr e) x)))
        ((eq? (car e) '*)
         (list '+
               (list '* (d (cadr e) x) (caddr e))
               (list '* (cadr e) (d (caddr e) x))))
        (else (error "d: unknown form"))))
(d '(+ (* x x) (* 3 x)) 'x)

; string building
(define (join sep xs)
  (cond ((null? xs) "")
        ((null? (cdr xs)) (car xs))
        (else (string-append (car xs) sep (join sep (cdr xs))))))
(join ", " '("a" "b" "c"))
