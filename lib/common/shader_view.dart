import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class ShaderView extends StatefulWidget {
  final String shaderName;
  final String timeUniform;
  final Function(Function(String uniformName, dynamic value))? onShaderLoaded;

  const ShaderView(
      {Key? key,
      required this.shaderName,
      this.timeUniform = 'uTime',
      this.onShaderLoaded})
      : super(key: key);

  @override
  State<ShaderView> createState() => _ShaderViewState();
}

class _ShaderViewState extends State<ShaderView>
    with SingleTickerProviderStateMixin {
  Future<FragmentShader>? _loader;
  final Map<String, _Uniform> _uniforms = {};

  FragmentShader? _shader;
  ValueNotifier<double>? _time;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ShaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loader = _loadShader("shaders/${widget.shaderName}.frag");
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FragmentShader>(
      future: _loader,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return CustomPaint(
              painter: _ShaderPainter(shader: snapshot.data!, repaint: _time));
        } else {
          if (snapshot.hasError) {
            print(snapshot.error);
          }

          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  Future<FragmentShader> _loadShader(String shaderName) async {
    try {
      final FragmentProgram program =
          await FragmentProgram.fromAsset(shaderName);
      await _getUniforms(shaderName);
      final timeUniform = _uniforms[widget.timeUniform];

      if (timeUniform != null && _ticker == null) {
        _time = ValueNotifier(0.0);
        _ticker = createTicker((elapsed) {
          final double elapsedSeconds = elapsed.inMilliseconds / 1000;
          _shader?.setFloat(timeUniform.index, elapsedSeconds);
          _time?.value = elapsedSeconds;
        });
        _ticker!.start();
      }

      _shader = program.fragmentShader();

      widget.onShaderLoaded?.call((uniformName, value) {
        final uniform = _uniforms[uniformName];

        if (uniform != null) {
          List<double> val = List.filled(uniform.size, 0, growable: false);

          if ((value.runtimeType == List<double>) &&
              value.length == uniform.size) {
            for (int i = 0; i < val.length; i++) {
              _shader?.setFloat(uniform.index + i, value[i]);
            }

            return;
          }

          switch (uniform.size) {
            case 1:
              val[0] = value as double;
              break;
            case 2:
              switch (value.runtimeType) {
                case Offset:
                  final offset = value as Offset;
                  val[0] = offset.dx;
                  val[1] = offset.dy;
                  break;
                case Size:
                  final size = value as Size;
                  val[0] = size.width;
                  val[1] = size.height;
                  break;
                case Point<double>:
                  final point = value as Point<double>;
                  val[0] = point.x;
                  val[1] = point.y;
                  break;
              }
              break;
            case 3:
              switch (value.runtimeType) {
                case Color:
                  final color = value as Color;
                  val[0] = color.red / 255;
                  val[1] = color.green / 255;
                  val[2] = color.blue / 255;
                  break;
                case int:
                  final color = value as int;
                  val[0] = (color >> 16 & 0xFF) / 255;
                  val[1] = (color >> 8 & 0xFF) / 255;
                  val[2] = (color & 0xFF) / 255;
                  break;
              }
              break;
            case 4:
              switch (value.runtimeType) {
                case Color:
                  final color = value as Color;
                  val[0] = color.red / 255;
                  val[1] = color.green / 255;
                  val[2] = color.blue / 255;
                  val[3] = color.alpha / 255;
                  break;
                case int:
                  final color = value as int;
                  val[0] = (color >> 16 & 0xFF) / 255;
                  val[1] = (color >> 8 & 0xFF) / 255;
                  val[2] = (color & 0xFF) / 255;
                  val[3] = (color >> 24 & 0xFF) / 255;
                  break;
                case Rectangle<double>:
                  final rect = value as Rectangle<double>;
                  val[0] = rect.left;
                  val[1] = rect.top;
                  val[2] = rect.width;
                  val[3] = rect.height;
                  break;
              }
          }

          for (int i = 0; i < val.length; i++) {
            _shader?.setFloat(uniform.index + i, val[i]);
          }
        }
      });

      return _shader!;
    } catch (e) {
      rethrow;
    }
  }

  Future<int?> _getUniforms(String shaderName) async {
    final Uint8List buffer =
        (await rootBundle.load(shaderName)).buffer.asUint8List();
    int uniformIndex = 0;
    int? timeUniform;

    _lookupBuffer(buffer, 0, (start, line) {
      final List<String> split = line.split(RegExp(r"\s+"));

      if (split.length == 3 && split[0] == 'uniform') {
        int? offset;

        switch (split[1]) {
          case 'float':
            offset = 1;
            break;
          case 'vec2':
            offset = 2;
            break;
          case 'vec3':
            offset = 3;
            break;
          case 'vec4':
            offset = 4;
            break;
        }

        if (offset != null) {
          _lookupBuffer(buffer, start, (_, line) {
            final List<String> s = line.split(RegExp(r"(\s+|[-*+\/\(\),])"));

            for (var i = 0; i < s.length; i++) {
              if (s[i] == split[2]) {
                _uniforms[s[i]] = _Uniform(uniformIndex, offset!);
                uniformIndex += offset;
                return true;
              }
            }

            return false;
          });
        }
      }

      return false;
    });

    return timeUniform;
  }

  void _lookupBuffer(
      Uint8List buffer, int start, bool Function(int, String) callback) {
    final StringBuffer sb = StringBuffer();

    for (var i = start; i < buffer.length; i++) {
      if (buffer[i] >= 32 && buffer[i] <= 126 && buffer[i] != 59) {
        sb.write(String.fromCharCode(buffer[i]));
      } else if (buffer[i] == 59) {
        if (sb.length == 0) {
          continue;
        }

        if (callback(i, sb.toString())) {
          return;
        }

        sb.clear();
      }
    }
  }
}

class _Uniform {
  final int index;
  final int size;

  _Uniform(this.index, this.size);
}

class _ShaderPainter extends CustomPainter {
  late final Paint _paint;

  _ShaderPainter({
    required FragmentShader shader,
    Listenable? repaint,
  }) : super(repaint: repaint) {
    _paint = Paint()..shader = shader;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(_ShaderPainter oldDelegate) => false;
}
