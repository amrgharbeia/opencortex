(defpackage :opencortex-gateway-manager-tests
  (:use :cl :fiveam :opencortex)
  (:export #:gateway-suite))

(in-package :opencortex-gateway-manager-tests)

(def-suite gateway-suite :description "Verification of the Gateway Manager skill")

(in-suite gateway-suite)

(test test-gateway-registration
  "Verify that the skill can register a new gateway metadata block."
  (let ((opencortex::*gateways* nil))
    (opencortex:skill-gateway-register :telegram '(:status :unverified))
    (is (getf (getf opencortex::*gateways* :telegram) :status))))

(test test-gateway-multiple-platforms
  "Verify that multiple gateways can be registered simultaneously."
  (let ((opencortex::*gateways* nil))
    (opencortex:skill-gateway-register :telegram '(:status :verified :token "abc123"))
    (opencortex:skill-gateway-register :signal '(:status :unverified))
    (is (eq (getf (getf opencortex::*gateways* :telegram) :status) :verified))
    (is (eq (getf (getf opencortex::*gateways* :signal) :status) :unverified))))
