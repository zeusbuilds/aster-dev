package dev.steenbakker.mobile_scanner

import android.app.Activity
import android.os.Looper
import androidx.camera.core.Camera
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraState
import androidx.camera.core.Preview
import androidx.camera.core.ZoomState
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.common.util.concurrent.SettableFuture
import io.flutter.view.TextureRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Exercise actual CameraX-future integration, including stale lifecycle replies. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
internal class CameraZoomOperationTest {
    private class Fixture {
        val activity = Robolectric.buildActivity(CameraZoomTestActivity::class.java).setup().get()
        val camera = Mockito.mock(Camera::class.java)
        val info = Mockito.mock(CameraInfo::class.java)
        val control = Mockito.mock(CameraControl::class.java)
        val provider = Mockito.mock(ProcessCameraProvider::class.java)
        val preview = Mockito.mock(Preview::class.java)
        val reportedZoom = Mockito.mock(ZoomState::class.java)
        val operation = SettableFuture.create<Void?>()
        var bound = true
        val successes = mutableListOf<CameraZoomState>()
        val failures = mutableListOf<Exception>()
        val scanner = MobileScanner(
            activity,
            Mockito.mock(TextureRegistry::class.java),
            { _, _, _, _ -> },
            { _ -> },
            Mockito.mock(DeviceOrientationListener::class.java),
        )

        init {
            Mockito.`when`(camera.cameraInfo).thenReturn(info)
            Mockito.`when`(camera.cameraControl).thenReturn(control)
            Mockito.`when`(provider.isBound(preview)).thenAnswer { bound }
            Mockito.doAnswer { bound = false; null }.`when`(provider).unbindAll()
            Mockito.`when`(reportedZoom.minZoomRatio).thenReturn(1f)
            Mockito.`when`(reportedZoom.maxZoomRatio).thenReturn(8f)
            Mockito.`when`(reportedZoom.zoomRatio).thenReturn(1f)
            Mockito.`when`(info.zoomState).thenReturn(MutableLiveData(reportedZoom))
            Mockito.`when`(info.torchState).thenReturn(MutableLiveData(0))
            Mockito.`when`(info.cameraState).thenReturn(MutableLiveData<CameraState>())
            Mockito.`when`(control.setZoomRatio(2f)).thenReturn(operation)
            setField("camera", camera)
            setField("cameraProvider", provider)
            setField("preview", preview)
        }

        private fun setField(name: String, value: Any) {
            MobileScanner::class.java.getDeclaredField(name).apply {
                isAccessible = true
                set(scanner, value)
            }
        }

        fun request() {
            scanner.setZoomRatioConfirmed(2.0, successes::add, failures::add)
        }

        fun complete() {
            operation.set(null)
            shadowOf(Looper.getMainLooper()).idle()
        }
    }

    @Test
    fun replyWaitsForCameraXAndUsesReadbackInsteadOfRequestedTarget() {
        val fixture = Fixture()
        fixture.request()
        assertTrue(fixture.successes.isEmpty())
        assertFalse(fixture.operation.isDone)
        Mockito.`when`(fixture.reportedZoom.zoomRatio).thenReturn(1.95f)
        fixture.complete()
        assertEquals(1, fixture.successes.size)
        assertEquals(1.95, fixture.successes.single().zoomRatio, 0.00001)
        assertTrue(fixture.failures.isEmpty())
    }

    @Test
    fun pauseInvalidatesAnOtherwiseSuccessfulLateCameraReply() {
        val fixture = Fixture()
        fixture.request()
        fixture.scanner.pause()
        fixture.complete()
        assertTrue(fixture.successes.isEmpty())
        assertTrue(fixture.failures.single() is ZoomWhenStopped)
    }

    @Test
    fun stopInvalidatesAnOtherwiseSuccessfulLateCameraReply() {
        val fixture = Fixture()
        fixture.request()
        fixture.scanner.stop()
        fixture.complete()
        assertTrue(fixture.successes.isEmpty())
        assertTrue(fixture.failures.single() is ZoomWhenStopped)
    }

    @Test
    fun failedCameraOperationNeverAcknowledgesRequestedRatio() {
        val fixture = Fixture()
        fixture.request()
        fixture.operation.setException(IllegalStateException("Camera rejected zoom"))
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(fixture.successes.isEmpty())
        assertEquals(1, fixture.failures.size)
    }

    @Test(expected = ZoomWhenStopped::class)
    fun cachedCameraObjectWithoutBoundPreviewCannotReportZoom() {
        val fixture = Fixture()
        fixture.bound = false
        fixture.scanner.getZoomState()
    }
}

class CameraZoomTestActivity : Activity(), LifecycleOwner {
    override val lifecycle = LifecycleRegistry(this)
}
