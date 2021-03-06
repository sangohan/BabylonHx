package com.babylonhx.tools.hdr;

import com.babylonhx.math.Vector3;
import com.babylonhx.math.Color3;
import com.babylonhx.math.SphericalPolynomial;
import com.babylonhx.math.SphericalHarmonics;
import com.babylonhx.tools.hdr.PanoramaToCubeMapTools.CubeMapInfo;
import com.babylonhx.materials.textures.BaseTexture;
import com.babylonhx.math.Tools as MathTools;

import lime.utils.Float32Array;

/**
 * ...
 * @author Krtolica Vujadin
 */

/**
 * Helper class dealing with the extraction of spherical polynomial dataArray
 * from a cube map.
 */
class CubeMapToSphericalPolynomialTools {
	
	private static var FileFaces:Array<FileFaceOrientation> = [
		new FileFaceOrientation("right", new Vector3(1, 0, 0), new Vector3(0, 0, -1), new Vector3(0, -1, 0)), // +X east
		new FileFaceOrientation("left", new Vector3(-1, 0, 0), new Vector3(0, 0, 1), new Vector3(0, -1, 0)), // -X west
		new FileFaceOrientation("up", new Vector3(0, 1, 0), new Vector3(1, 0, 0), new Vector3(0, 0, 1)), // +Y north
		new FileFaceOrientation("down", new Vector3(0, -1, 0), new Vector3(1, 0, 0), new Vector3(0, 0, -1)), // -Y south
		new FileFaceOrientation("front", new Vector3(0, 0, 1), new Vector3(1, 0, 0), new Vector3(0, -1, 0)), // +Z top
		new FileFaceOrientation("back", new Vector3(0, 0, -1), new Vector3(-1, 0, 0), new Vector3(0, -1, 0))// -Z bottom
	];
	
	/**
	 * Converts a texture to the according Spherical Polynomial data. 
	 * This extracts the first 3 orders only as they are the only one used in the lighting.
	 * 
	 * @param texture The texture to extract the information from.
	 * @return The Spherical Polynomial data.
	 */
	public static function ConvertCubeMapTextureToSphericalPolynomial(texture:BaseTexture):SphericalPolynomial {
		if (!texture.isCube) {
			// Only supports cube Textures currently.
			return null;
		}
		
		var size = texture.getSize().width;
		var right = texture.readPixels(0);
		var left = texture.readPixels(1);
		var up = texture.readPixels(2);
		var down = texture.readPixels(3);
		var front = texture.readPixels(4);
		var back = texture.readPixels(5);
		
		var gammaSpace = texture.gammaSpace;
		// Always read as RGBA.
		var format = Engine.TEXTUREFORMAT_RGBA;
		var type = Engine.TEXTURETYPE_UNSIGNED_INT;
		if (/*texture.textureType && */texture.textureType != Engine.TEXTURETYPE_UNSIGNED_INT) {
			type = Engine.TEXTURETYPE_FLOAT;
		}
		
		var cubeInfo:CubeMapInfo = {
			size: size,
			right: right,
			left: left,
			up: up,
			down: down,
			front: front,
			back: back,
			format: format,
			type: type,
			gammaSpace: gammaSpace
		};
		
		return ConvertCubeMapToSphericalPolynomial(cubeInfo);
	}
	
	/**
	 * Converts a cubemap to the according Spherical Polynomial data. 
	 * This extracts the first 3 orders only as they are the only one used in the lighting.
	 * 
	 * @param cubeInfo The Cube map to extract the information from.
	 * @return The Spherical Polynomial data.
	 */
	public static function ConvertCubeMapToSphericalPolynomial(cubeInfo:CubeMapInfo):SphericalPolynomial {
		var sphericalHarmonics = new SphericalHarmonics();
		var totalSolidAngle = 0.0;
		
		// The (u,v) range is [-1,+1], so the distance between each texel is 2/Size.
		var du = 2.0 / cubeInfo.size;
		var dv = du;
		
		// The (u,v) of the first texel is half a texel from the corner (-1,-1).
		var minUV = du * 0.5 - 1.0;
		
		for (faceIndex in 0...6) {
			var fileFace = FileFaces[faceIndex];			
			var dataArray:Float32Array = Reflect.field(cubeInfo, fileFace.name);
			var v = minUV;
			
			// TODO: we could perform the summation directly into a SphericalPolynomial (SP), which is more efficient than SphericalHarmonic (SH).
			// This is possible because during the summation we do not need the SH-specific properties, e.g. orthogonality.
			// Because SP is still linear, so summation is fine in that basis.
			
			var stride = cubeInfo.format == Engine.TEXTUREFORMAT_RGBA ? 4 : 3;
			for (y in 0...cubeInfo.size) {
				var u = minUV;
				
				for (x in 0...cubeInfo.size) {
					// World direction (not normalised)
					var worldDirection =
						fileFace.worldAxisForFileX.scale(u).add(
							fileFace.worldAxisForFileY.scale(v)).add(
								fileFace.worldAxisForNormal);
					worldDirection.normalize();
					
					var deltaSolidAngle = Math.pow(1.0 + u * u + v * v, -3.0 / 2.0);
					
					var r = dataArray[(y * cubeInfo.size * stride) + (x * stride) + 0];
                    var g = dataArray[(y * cubeInfo.size * stride) + (x * stride) + 1];
                    var b = dataArray[(y * cubeInfo.size * stride) + (x * stride) + 2];
					
					// Handle Integer types.
					if (cubeInfo.type == Engine.TEXTURETYPE_UNSIGNED_INT) {
						r /= 255;
						g /= 255;
						b /= 255;
					}
					
					// Handle Gamma space textures.
					if (cubeInfo.gammaSpace) {
						r = Math.pow(MathTools.Clamp(r), MathTools.ToLinearSpace);
						g = Math.pow(MathTools.Clamp(g), MathTools.ToLinearSpace);
						b = Math.pow(MathTools.Clamp(b), MathTools.ToLinearSpace);
					}
					
					var color = new Color3(r, g, b);
					
					sphericalHarmonics.addLight(worldDirection, color, deltaSolidAngle);
					
					totalSolidAngle += deltaSolidAngle;
					
					u += du;
				}
				
				v += dv;
			}
		}
		
		// Solid angle for entire sphere is 4*pi
		var sphereSolidAngle = 4.0 * Math.PI;
		
		// Adjust the solid angle to allow for how many faces we processed.
		var facesProcessed = 6.0;
		var expectedSolidAngle = sphereSolidAngle * facesProcessed / 6.0;
		
		// Adjust the harmonics so that the accumulated solid angle matches the expected solid angle. 
		// This is needed because the numerical integration over the cube uses a 
		// small angle approximation of solid angle for each texel (see deltaSolidAngle),
		// and also to compensate for accumulative error due to float precision in the summation.
		var correctionFactor = expectedSolidAngle / totalSolidAngle;
		sphericalHarmonics.scale(correctionFactor);
		
		sphericalHarmonics.convertIncidentRadianceToIrradiance();
		sphericalHarmonics.convertIrradianceToLambertianRadiance();
		
		return SphericalPolynomial.getSphericalPolynomialFromHarmonics(sphericalHarmonics);
	}
	
}
