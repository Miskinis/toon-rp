using System;
using DELTation.ToonRP.Shadows.Blobs;
using UnityEngine;
using UnityEngine.Serialization;

namespace DELTation.ToonRP.Shadows
{
    [Serializable]
    public struct ToonShadowSettings
    {
        public enum ShadowMode
        {
            Off = 0,
            ShadowMapping,
            Blobs,
        }

        public ShadowMode Mode;

        [Range(0.0f, 1.0f)]
        public float Threshold;
        public bool CrispAntiAliased;
        [Range(0.0f, 1.0f)]
        public float Smoothness;
        [Min(0f)]
        public float MaxDistance;
        [Range(0.001f, 1f)]
        public float DistanceFade;

        public Texture2D Pattern;
        public Vector3 PatternScale;

        [Min(0f)]
        [Tooltip("Multiplier applied to the shadow pattern mask. 3 keeps the stylized point/spot shadow look.")]
        public float PatternStrength;

        // Serialization migration marker: assets created before PatternStrength existed read 0.
        // In that case GetPatternStrength falls back to 3 instead of disabling the pattern.
        [HideInInspector] public bool PatternStrengthSet;

        [FormerlySerializedAs("Vsm")] public ToonShadowMapsSettings ShadowMaps;
        public ToonBlobShadowsSettings Blobs;

        public float GetPatternStrength() => PatternStrengthSet ? PatternStrength : 3.0f;
    }
}