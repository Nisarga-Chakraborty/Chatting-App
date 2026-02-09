import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:studenthub_chat/screens/home_screen.dart';
import 'package:pinput/pinput.dart';

class AuthScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return AuthScreenState();
  }
}

class AuthScreenState extends State<AuthScreen> {
  var _isLogin = true;
  var _enteredEmail = "";
  var _enteredPassword = "";
  var _enteredUsername = "";
  var _isAuthenticating = false;
  String? _phoneNumber;
  String _verificationId = "";
  final _otpController = TextEditingController();
  var showOTPField = false;

  final _formKey = GlobalKey<FormState>();

  void verifyOTP() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a valid 6-digit OTP")),
      );
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (ctx) => HomeScreen()));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("OTP Verification failed: ${e.message}")),
      );
    } finally {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  Widget otpUI() {
    return Pinput(
      controller: _otpController,
      length: 6,
      defaultPinTheme: PinTheme(
        width: 56,
        height: 56,
        textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      focusedPinTheme: PinTheme(
        width: 56,
        height: 56,
        textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> verifyPhoneNumber() async {
    // Enhanced phone number validation
    if (_phoneNumber == null || _phoneNumber!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Please enter a phone number")));
      return;
    }

    // Validate phone number format
    final phone = _phoneNumber!.trim();
    if (!phone.startsWith('+')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Phone number must start with country code (e.g., +1)"),
        ),
      );
      return;
    }

    // Remove non-digit characters except + at beginning
    final digitsOnly = phone.substring(1).replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please enter a valid phone number with area code"),
        ),
      );
      return;
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute(builder: (ctx) => HomeScreen()));
        },
        verificationFailed: (FirebaseAuthException e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Verification failed: ${e.message}")),
          );
          setState(() {
            _isAuthenticating = false;
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isAuthenticating = false;
            showOTPField = true;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("OTP sent to $phone")));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() {
        _isAuthenticating = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> submit() async {
    final isValid = _formKey.currentState!.validate();
    if (!isValid) return;

    _formKey.currentState!.save();

    // Enhanced validation for signup
    if (!_isLogin) {
      // Phone number validation for signup
      if (_phoneNumber == null || _phoneNumber!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Phone number is required for signup"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Validate phone number format
      final phone = _phoneNumber!.trim();
      if (!phone.startsWith('+')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Phone number must start with country code (e.g., +1)",
            ),
          ),
        );
        return;
      }

      // Validate phone number length (country code + minimum digits)
      final digitsOnly = phone.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.length < 7) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Please enter a valid phone number with at least 7 digits after country code",
            ),
          ),
        );
        return;
      }

      // Additional password confirmation validation
      if (_enteredPassword.trim().length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Password must be at least 6 characters")),
        );
        return;
      }
    }

    setState(() {
      _isAuthenticating = true;
    });

    try {
      if (_isLogin) {
        // Login logic
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _enteredEmail,
          password: _enteredPassword,
        );
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (ctx) => HomeScreen()));
      } else {
        // Signup logic
        final userCredentials = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _enteredEmail.trim(),
              password: _enteredPassword,
            );

        // Format phone number before saving
        final formattedPhone = _phoneNumber!.trim();

        await FirebaseFirestore.instance
            .collection("users")
            .doc(userCredentials.user!.uid)
            .set({
              "username": _enteredUsername.trim(),
              "email": _enteredEmail.trim(),
              "phone": formattedPhone,
              "createdAt": FieldValue.serverTimestamp(),
              "updatedAt": FieldValue.serverTimestamp(),
            });

        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (ctx) => HomeScreen()));
      }
    } on FirebaseAuthException catch (error) {
      String message = "Authentication Failed";
      if (error.code == "email-already-in-use") {
        message = "This email is already in use.";
      } else if (error.code == "user-not-found") {
        message = "User with this email not found.";
      } else if (error.code == "wrong-password") {
        message = "Incorrect password.";
      } else if (error.code == "invalid-email") {
        message = "Invalid email address format.";
      } else if (error.code == "weak-password") {
        message = "Password is too weak. Use at least 6 characters.";
      } else if (error.code == "too-many-requests") {
        message = "Too many attempts. Try again later.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("An error occurred: $e")));
    } finally {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Authentication',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 3, 38, 99),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/auth_image.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 160),
                Card(
                  elevation: 8,
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!_isLogin)
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: "Username",
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (!_isLogin &&
                                    (value == null || value.trim().isEmpty)) {
                                  return "Please enter a username.";
                                }
                                return null;
                              },
                              onSaved: (value) {
                                _enteredUsername = value!;
                              },
                            ),
                          if (!_isLogin) const SizedBox(height: 10),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: "Email",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty ||
                                  !value.contains("@") ||
                                  value.trim().length < 5) {
                                return "Please enter a valid email address.";
                              }
                              return null;
                            },
                            onSaved: (value) {
                              _enteredEmail = value!;
                            },
                          ),
                          SizedBox(height: 10),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: "Password",
                              border: OutlineInputBorder(),
                            ),
                            obscureText: true,
                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty ||
                                  value.trim().length < 6) {
                                return "Password must be at least 6 characters long.";
                              }
                              return null;
                            },
                            onSaved: (value) {
                              _enteredPassword = value!;
                            },
                            onChanged: (value) {
                              _enteredPassword = value;
                            },
                          ),
                          if (!_isLogin) SizedBox(height: 10),
                          if (!_isLogin)
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: "Confirm Password",
                                border: OutlineInputBorder(),
                              ),
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Please confirm your password.";
                                }
                                if (value != _enteredPassword) {
                                  return "Passwords do not match.";
                                }
                                return null;
                              },
                            ),
                          const SizedBox(height: 10),
                          if (showOTPField == false)
                            TextFormField(
                              decoration: InputDecoration(
                                label: Text("Phone Number"),
                                border: OutlineInputBorder(),
                                hintText: "+1234567890",
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                // Enhanced validation for phone number
                                if (!_isLogin) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Phone number is required";
                                  }
                                  if (!value.startsWith('+')) {
                                    return "Must start with country code (e.g., +1)";
                                  }
                                  // Check if has enough digits after +
                                  final digits = value
                                      .substring(1)
                                      .replaceAll(RegExp(r'\D'), '');
                                  if (digits.length < 7) {
                                    return "Enter valid phone number with area code";
                                  }
                                }
                                return null;
                              },
                              onSaved: (value) {
                                _phoneNumber = value;
                              },
                              onChanged: (value) {
                                _phoneNumber = value;
                              },
                            ),
                          if (showOTPField == true) otpUI(),
                          const SizedBox(height: 10),
                          if (showOTPField == false)
                            ElevatedButton(
                              child: Text("Get OTP"),
                              onPressed: () {
                                verifyPhoneNumber();
                              },
                            ),
                          if (showOTPField == true)
                            ElevatedButton(
                              child: Text("Verify OTP"),
                              onPressed: verifyOTP,
                            ),
                          const SizedBox(height: 10),
                          if (_isAuthenticating)
                            const CircularProgressIndicator(),
                          if (!_isAuthenticating)
                            ElevatedButton(
                              onPressed: submit,
                              child: Text(_isLogin ? "Login" : "Sign Up"),
                            ),
                          TextButton(
                            child: Text(
                              _isLogin
                                  ? "Don't have an account? Sign Up"
                                  : "Already have an account? Login",
                            ),
                            onPressed: () {
                              setState(() {
                                _isLogin = !_isLogin;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
