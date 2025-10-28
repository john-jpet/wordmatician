extends ColorRect

func _ready():
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.17, 0.18, 0.27))
	grad.add_point(0.5, Color(0.11, 0.14, 0.21))
	grad.add_point(1.0, Color(0.06, 0.09, 0.15))

	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad

	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
		shader_type canvas_item;
		uniform sampler2D grad_tex : source_color;
		void fragment() {
			COLOR = texture(grad_tex, vec2(UV.x * 0.8 + 0.1, UV.y));
		}
	"""
	mat.set_shader_parameter("grad_tex", grad_tex)
	self.material = mat
