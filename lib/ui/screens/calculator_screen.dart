import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:math_expressions/math_expressions.dart';
import '../../providers/session_provider.dart';
import '../../providers/handshake_provider.dart';
import '../../utils/crypto_utils.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _input = '';
  String _result = '';
  bool _isLoading = false;

  // Material You Dark Theme Colors
  final Color _bgColor = const Color(0xFF1C1B1F);
  final Color _numBtnColor = const Color(0xFF313033);
  final Color _opBtnColor = const Color(0xFF4A4458);
  final Color _eqBtnColor = const Color(0xFFD0BCFF);
  final Color _clearBtnColor = const Color(0xFF4A4458);

  final Color _numTextColor = const Color(0xFFE6E1E5);
  final Color _opTextColor = const Color(0xFFE8DEF8);
  final Color _eqTextColor = const Color(0xFF381E72);
  final Color _clearTextColor = const Color(0xFFE8DEF8);

  void _onButtonPressed(String value) async {
    if (_isLoading) return;

    if (value == 'AC') {
      setState(() {
        _input = '';
        _result = '';
      });
    } else if (value == '⌫') {
      setState(() {
        if (_input.isNotEmpty) {
          _input = _input.substring(0, _input.length - 1);
          _evaluateMath();
        }
      });
    } else if (value == '=') {
      await _checkDecoySequence();
    } else {
      setState(() {
        _input += value;
        _evaluateMath();
      });
    }
  }

  Future<void> _checkDecoySequence() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    
    final decoyPassword = prefs.getString('decoy_password');

    // Remove any trailing operations for clean check
    String cleanInput = _input.trim();
    
    if (cleanInput == decoyPassword) {
      // Trigger unlock sequence
      setState(() {
        _isLoading = true;
      });

      try {
        final handshake = Provider.of<HandshakeProvider>(context, listen: false);
        final doc = handshake.couplesDocument;
        
        final saltHex = doc?.cryptoSalt ?? '00000000000000000000000000000000';
        
        // This is CPU intensive and might block the UI thread briefly.
        // In a production app, use compute() to spawn an isolate.
        final derivedKey = CryptoUtils.deriveKey(cleanInput, saltHex);
        
        Provider.of<SessionProvider>(context, listen: false).unlock(derivedKey);

        if (mounted) {
          context.go('/vault');
        }
      } catch (e) {
        print("Error deriving key: $e");
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      // Normal calculator evaluation behavior when '=' is pressed
      if (_result.isNotEmpty && _result != 'Error') {
        setState(() {
          _input = _result;
          _result = '';
        });
      }
    }
  }

  void _evaluateMath() {
    if (_input.isEmpty) {
      _result = '';
      return;
    }
    try {
      Parser p = Parser();
      // Replace symbols for math_expressions
      String evalStr = _input.replaceAll('×', '*').replaceAll('÷', '/');
      Expression exp = p.parse(evalStr);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);
      
      setState(() {
        _result = eval.toString();
        if (_result.endsWith('.0')) {
          _result = _result.substring(0, _result.length - 2);
        }
      });
    } catch (e) {
      setState(() {
        _result = ''; // Don't show error while typing
      });
    }
  }

  Widget _buildButton(String text, Color bgColor, Color textColor) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: InkWell(
          onTap: () => _onButtonPressed(text),
          borderRadius: BorderRadius.circular(40), // Fully rounded for Material You
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillButton(String text, Color bgColor, Color textColor) {
    return Expanded(
      flex: 2,
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: InkWell(
          onTap: () => _onButtonPressed(text),
          borderRadius: BorderRadius.circular(40),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Display Area
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                alignment: Alignment.bottomRight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _input,
                      style: TextStyle(fontSize: 48, color: _numTextColor, fontWeight: FontWeight.w300),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _isLoading
                        ? CircularProgressIndicator(color: _eqBtnColor)
                        : Text(
                            _result,
                            style: TextStyle(fontSize: 32, color: _numTextColor.withOpacity(0.6), fontWeight: FontWeight.w300),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                ),
              ),
            ),
            
            // Keypad Area
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _buildButton('AC', _clearBtnColor, _clearTextColor),
                          _buildButton('(', _opBtnColor, _opTextColor),
                          _buildButton(')', _opBtnColor, _opTextColor),
                          _buildButton('÷', _opBtnColor, _opTextColor),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildButton('7', _numBtnColor, _numTextColor),
                          _buildButton('8', _numBtnColor, _numTextColor),
                          _buildButton('9', _numBtnColor, _numTextColor),
                          _buildButton('×', _opBtnColor, _opTextColor),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildButton('4', _numBtnColor, _numTextColor),
                          _buildButton('5', _numBtnColor, _numTextColor),
                          _buildButton('6', _numBtnColor, _numTextColor),
                          _buildButton('-', _opBtnColor, _opTextColor),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildButton('1', _numBtnColor, _numTextColor),
                          _buildButton('2', _numBtnColor, _numTextColor),
                          _buildButton('3', _numBtnColor, _numTextColor),
                          _buildButton('+', _opBtnColor, _opTextColor),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          _buildPillButton('0', _numBtnColor, _numTextColor),
                          _buildButton('.', _numBtnColor, _numTextColor),
                          _buildButton('=', _eqBtnColor, _eqTextColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
