package com.example.asterdev

import org.junit.Assert.assertEquals
import org.junit.Test

class LocalNetworkPermissionRequestTest {
    @Test
    fun grantCompletesOnlyOnce() {
        val results = mutableListOf<Boolean?>()
        val request = LocalNetworkPermissionRequest { results.add(it) }
        request.complete(true)
        request.complete(false)
        request.complete(null)
        assertEquals(listOf(true), results)
    }

    @Test
    fun denialCompletesOnlyOnce() {
        val results = mutableListOf<Boolean?>()
        val request = LocalNetworkPermissionRequest { results.add(it) }
        request.complete(false)
        request.complete(true)
        assertEquals(listOf(false), results)
    }

    @Test
    fun timeoutOrDetachDoesNotRespondAgainWhenAndroidReturns() {
        val results = mutableListOf<Boolean?>()
        val request = LocalNetworkPermissionRequest { results.add(it) }
        request.complete(null)
        request.complete(true)
        assertEquals(listOf<Boolean?>(null), results)
    }
}
