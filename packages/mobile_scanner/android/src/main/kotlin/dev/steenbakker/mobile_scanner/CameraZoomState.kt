package dev.steenbakker.mobile_scanner

/** A validated snapshot of CameraX ratios, without normalized-slider conversion. */
internal data class CameraZoomState(
    val minZoomRatio: Double,
    val maxZoomRatio: Double,
    val zoomRatio: Double,
) {
    init {
        require(minZoomRatio.isFinite() && minZoomRatio > 0.0)
        require(maxZoomRatio.isFinite() && maxZoomRatio >= minZoomRatio)
        require(zoomRatio.isFinite() && zoomRatio >= minZoomRatio - 0.0001 &&
            zoomRatio <= maxZoomRatio + 0.0001)
    }

    fun requireSupportedRatio(ratio: Double) {
        require(ratio.isFinite() && ratio in minZoomRatio..maxZoomRatio) {
            "Zoom ratio is outside the active camera's supported range."
        }
    }

    fun serialize(): Map<String, Double> = mapOf(
        "minZoomRatio" to minZoomRatio,
        "maxZoomRatio" to maxZoomRatio,
        "zoomRatio" to zoomRatio,
    )
}
