package dev.steenbakker.mobile_scanner

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class CameraZoomStateTest {
    @Test
    fun ratiosAreReportedWithoutNormalizedSliderMapping() {
        val state = CameraZoomState(1.0, 8.0, 3.0)
        state.requireSupportedRatio(2.0)
        assertEquals(3.0, state.serialize()["zoomRatio"])
        assertEquals(1.0, state.serialize()["minZoomRatio"])
        assertEquals(8.0, state.serialize()["maxZoomRatio"])
    }

    @Test
    fun hardwareMayHaveFractionalBoundsAndNoThreeTimesPreset() {
        val state = CameraZoomState(0.5, 2.4, 1.0)
        state.requireSupportedRatio(0.5)
        state.requireSupportedRatio(2.4)
        assertFailsWith<IllegalArgumentException> { state.requireSupportedRatio(3.0) }
    }

    @Test
    fun fixedZoomCameraHasAnAccurateSingleRatio() {
        CameraZoomState(1.0, 1.0, 1.0).requireSupportedRatio(1.0)
        assertFailsWith<IllegalArgumentException> {
            CameraZoomState(1.0, 1.0, 1.0).requireSupportedRatio(2.0)
        }
    }

    @Test
    fun invalidRequestsAreRejectedInsteadOfClampedOrReportedAsApplied() {
        val state = CameraZoomState(1.0, 4.0, 1.0)
        for (ratio in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, 0.0, 0.9, 4.1)) {
            assertFailsWith<IllegalArgumentException> { state.requireSupportedRatio(ratio) }
        }
    }

    @Test
    fun unavailableOrInvalidHardwareDataIsNotReplacedWithDefaultBounds() {
        for (minimum in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, -1.0)) {
            assertFailsWith<IllegalArgumentException> { CameraZoomState(minimum, 4.0, 1.0) }
        }
        assertFailsWith<IllegalArgumentException> { CameraZoomState(2.0, 1.0, 1.0) }
        assertFailsWith<IllegalArgumentException> { CameraZoomState(1.0, 4.0, 5.0) }
        assertFailsWith<IllegalArgumentException> { CameraZoomState(1.0, 4.0, Double.NaN) }
    }
}
