;;;; -*- mode: lisp; indent-tabs-mode: nil -*-
;;;; poly1305.lisp -- RFC 7539 poly1305 message authentication code


(in-package :crypto)


(defclass poly1305 (mac)
  ((accumulator :accessor poly1305-accumulator
                :initform (make-array 5 :element-type '(unsigned-byte 32))
                :type (simple-array (unsigned-byte 32) (5)))
   (r :accessor poly1305-r
      :initform (make-array 4 :element-type '(unsigned-byte 32))
      :type (simple-array (unsigned-byte 32) (4)))
   (s :accessor poly1305-s
      :initform (make-array 4 :element-type '(unsigned-byte 32))
      :type (simple-array (unsigned-byte 32) (4)))
   (buffer :accessor poly1305-buffer
           :initform (make-array 16 :element-type '(unsigned-byte 8))
           :type (simple-array (unsigned-byte 8) (16)))
   (buffer-length :accessor poly1305-buffer-length
                  :initform 0
                  :type (integer 0 16))))

(defun make-poly1305 (key)
  (declare (type (simple-array (unsigned-byte 8) (*)) key))
  (unless (= (length key) 32)
    (error 'invalid-mac-parameter
           :mac-name 'poly1305
           :message "The key length must be 32 bytes"))
  (make-instance 'poly1305 :key key))

(defmethod shared-initialize :after ((mac poly1305) slot-names &rest initargs &key key &allow-other-keys)
  (declare (ignore slot-names initargs)
           (type (simple-array (unsigned-byte 8) (32)) key))
  (let ((accumulator (poly1305-accumulator mac))
        (r (poly1305-r mac))
        (s (poly1305-s mac)))
    (declare (type (simple-array (unsigned-byte 32) (5)) accumulator)
             (type (simple-array (unsigned-byte 32) (4)) r s))
    (fill accumulator 0)
    (setf (aref r 0) (logand (ub32ref/le key 0) #x0fffffff)
          (aref r 1) (logand (ub32ref/le key 4) #x0ffffffc)
          (aref r 2) (logand (ub32ref/le key 8) #x0ffffffc)
          (aref r 3) (logand (ub32ref/le key 12) #x0ffffffc))
    (setf (aref s 0) (ub32ref/le key 16)
          (aref s 1) (ub32ref/le key 20)
          (aref s 2) (ub32ref/le key 24)
          (aref s 3) (ub32ref/le key 28))
    (setf (poly1305-buffer-length mac) 0)
    mac))

(defun poly1305-process-full-blocks (accumulator r data start remaining final)
  (declare (type (simple-array (unsigned-byte 32) (5)) accumulator)
           (type (simple-array (unsigned-byte 32) (4)) r)
           (type (simple-array (unsigned-byte 8) (*)) data)
           (type index start remaining)
           (type boolean final)
           (optimize (speed 3) (space 0) (safety 0) (debug 0)))
  (let* ((hibit (if final 0 1))
         (h0 (aref accumulator 0))
         (h1 (aref accumulator 1))
         (h2 (aref accumulator 2))
         (h3 (aref accumulator 3))
         (h4 (aref accumulator 4))
         (r0 (aref r 0))
         (r1 (aref r 1))
         (r2 (aref r 2))
         (r3 (aref r 3))
         (rr0 (mod32* (mod32ash r0 -2) 5))
         (rr1 (mod32+ (mod32ash r1 -2) r1))
         (rr2 (mod32+ (mod32ash r2 -2) r2))
         (rr3 (mod32+ (mod32ash r3 -2) r3)))
    (declare (type (unsigned-byte 32) hibit h0 h1 h2 h3 h4 r0 r1 r2 r3 rr0 rr1 rr2 rr3))
    (loop while (>= remaining 16) do
      (let* ((s0 (mod64+ h0 (ub32ref/le data start)))
             (s1 (mod64+ h1 (ub32ref/le data (+ start 4))))
             (s2 (mod64+ h2 (ub32ref/le data (+ start 8))))
             (s3 (mod64+ h3 (ub32ref/le data (+ start 12))))
             (s4 (mod32+ h4 hibit))
             (x0 (mod64+ (mod64* s0 r0)
                         (mod64+ (mod64* s1 rr3)
                                 (mod64+ (mod64* s2 rr2)
                                         (mod64+ (mod64* s3 rr1)
                                                 (mod64* s4 rr0))))))
             (x1 (mod64+ (mod64* s0 r1)
                         (mod64+ (mod64* s1 r0)
                                 (mod64+ (mod64* s2 rr3)
                                         (mod64+ (mod64* s3 rr2)
                                                 (mod64* s4 rr1))))))
             (x2 (mod64+ (mod64* s0 r2)
                         (mod64+ (mod64* s1 r1)
                                 (mod64+ (mod64* s2 r0)
                                         (mod64+ (mod64* s3 rr3)
                                                 (mod64* s4 rr2))))))
             (x3 (mod64+ (mod64* s0 r3)
                         (mod64+ (mod64* s1 r2)
                                 (mod64+ (mod64* s2 r1)
                                         (mod64+ (mod64* s3 r0)
                                                 (mod64* s4 rr3))))))
             (x4 (mod32* s4 (logand r0 3)))
             (u5 (mod32+ x4 (logand (mod64ash x3 -32) #xffffffff)))
             (u0 (mod64+ (mod64* (mod32ash u5 -2) 5)
                         (logand x0 #xffffffff)))
             (u1 (mod64+ (mod64ash u0 -32)
                         (mod64+ (logand x1 #xffffffff)
                                 (mod64ash x0 -32))))
             (u2 (mod64+ (mod64ash u1 -32)
                         (mod64+ (logand x2 #xffffffff)
                                 (mod64ash x1 -32))))
             (u3 (mod64+ (mod64ash u2 -32)
                         (mod64+ (logand x3 #xffffffff)
                                 (mod64ash x2 -32))))
             (u4 (mod64+ (mod64ash u3 -32)
                         (logand u5 3))))
        (declare (type (unsigned-byte 64) s0 s1 s2 s3 x0 x1 x2 x3 u0 u1 u2 u3 u4)
                 (type (unsigned-byte 32) s4 x4 u5))
        (setf h0 (logand u0 #xffffffff)
              h1 (logand u1 #xffffffff)
              h2 (logand u2 #xffffffff)
              h3 (logand u3 #xffffffff)
              h4 (logand u4 #xffffffff))
        (incf start 16)
        (decf remaining 16)))
    (setf (aref accumulator 0) h0
          (aref accumulator 1) h1
          (aref accumulator 2) h2
          (aref accumulator 3) h3
          (aref accumulator 4) h4)
    (values start remaining)))

(defun update-poly1305 (mac data &key (start 0) (end (length data)))
  (declare (type (simple-array (unsigned-byte 8) (*)) data)
           (type fixnum start end)
           (optimize (speed 3) (space 0) (safety 1) (debug 0)))
  (let ((buffer (poly1305-buffer mac))
        (buffer-length (poly1305-buffer-length mac))
        (accumulator (poly1305-accumulator mac))
        (r (poly1305-r mac))
        (remaining (- end start)))
    (declare (type (simple-array (unsigned-byte 8) (16)) buffer)
             (type (integer 0 16) buffer-length)
             (type (simple-array (unsigned-byte 32) (5)) accumulator)
             (type (simple-array (unsigned-byte 32) (4)) r)
             (type fixnum remaining))

    ;; Fill the buffer with new data if necessary
    (when (plusp buffer-length)
      (let ((n (min remaining (- 16 buffer-length))))
        (declare (type (integer 0 16) n))
        (replace buffer data
                 :start1 buffer-length
                 :start2 start
                 :end2 (+ start n))
        (incf buffer-length n)
        (incf start n)
        (decf remaining n)))

    ;; Process the buffer
    (when (= buffer-length 16)
      (poly1305-process-full-blocks accumulator r buffer 0 16 nil)
      (setf buffer-length 0))

    ;; Process the data
    (multiple-value-setq (start remaining)
      (poly1305-process-full-blocks accumulator r data start remaining nil))

    ;; Put the remaining data in the buffer
    (when (plusp remaining)
      (replace buffer data :start1 0 :start2 start :end2 end)
      (setf buffer-length remaining))

    ;; Save the state
    (setf (poly1305-buffer-length mac) buffer-length)
    (values)))

(defun poly1305-digest (mac)
  (let ((buffer (copy-seq (poly1305-buffer mac)))
        (buffer-length (poly1305-buffer-length mac))
        (accumulator (copy-seq (poly1305-accumulator mac)))
        (r (poly1305-r mac))
        (s (poly1305-s mac)))
    (declare (type (simple-array (unsigned-byte 8) (16)) buffer)
             (type (integer 0 16) buffer-length)
             (type (simple-array (unsigned-byte 32) (5)) accumulator)
             (type (simple-array (unsigned-byte 32) (4)) r s))

    ;; Process the buffer
    (when (plusp buffer-length)
      (setf (aref buffer buffer-length) 1)
      (when (< buffer-length 15)
        (fill buffer 0 :start (1+ buffer-length) :end 16))
      (poly1305-process-full-blocks accumulator r buffer 0 16 t))

    ;; Produce the tag
    (let* ((h0 (aref accumulator 0))
           (h1 (aref accumulator 1))
           (h2 (aref accumulator 2))
           (h3 (aref accumulator 3))
           (h4 (aref accumulator 4))
           (u0 (mod64+ 5 h0))
           (u1 (mod64+ (mod64ash u0 -32) h1))
           (u2 (mod64+ (mod64ash u1 -32) h2))
           (u3 (mod64+ (mod64ash u2 -32) h3))
           (u4 (mod64+ (mod64ash u3 -32) h4))
           (uu0 (mod64+ (mod64* (mod64ash u4 -2) 5)
                        (mod64+ h0 (aref s 0))))
           (uu1 (mod64+ (mod64ash uu0 -32)
                        (mod64+ h1 (aref s 1))))
           (uu2 (mod64+ (mod64ash uu1 -32)
                        (mod64+ h2 (aref s 2))))
           (uu3 (mod64+ (mod64ash uu2 -32)
                        (mod64+ h3 (aref s 3))))
           (tag (make-array 16 :element-type '(unsigned-byte 8))))
      (declare (type (unsigned-byte 32) h0 h1 h2 h3 h4)
               (type (unsigned-byte 64) u0 u1 u2 u3 u4 uu0 uu1 uu2 uu3)
               (type (simple-array (unsigned-byte 8) (16)) tag))
      (setf (ub32ref/le tag 0) (logand uu0 #xffffffff)
            (ub32ref/le tag 4) (logand uu1 #xffffffff)
            (ub32ref/le tag 8) (logand uu2 #xffffffff)
            (ub32ref/le tag 12) (logand uu3 #xffffffff))
      tag)))

(defmac poly1305
        make-poly1305
        update-poly1305
        poly1305-digest)
