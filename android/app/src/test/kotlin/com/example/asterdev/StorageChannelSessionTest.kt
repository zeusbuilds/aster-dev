package com.example.asterdev

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StorageChannelSessionTest {
    @Test
    fun admitsOnlyOneConcurrentOperationAndCompletesExactlyOnce() {
        val session = StorageChannelSession()
        val ready = CountDownLatch(workerCount)
        val start = CountDownLatch(1)
        val winners = AtomicInteger()
        val executor = Executors.newFixedThreadPool(workerCount)

        repeat(workerCount) {
            executor.execute {
                ready.countDown()
                if (start.await(5, TimeUnit.SECONDS) && session.tryBegin()) {
                    winners.incrementAndGet()
                }
            }
        }

        val allWorkersReady = ready.await(5, TimeUnit.SECONDS)
        start.countDown()
        assertTrue(allWorkersReady)
        executor.shutdown()
        assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
        assertEquals(1, winners.get())
        assertTrue(session.complete())
        assertFalse(session.complete())
        assertTrue(session.tryBegin())
    }

    @Test
    fun invalidationSuppressesPendingAndFutureCompletions() {
        val session = StorageChannelSession()

        assertTrue(session.tryBegin())
        session.invalidate()

        assertFalse(session.complete())
        assertFalse(session.tryBegin())
    }

    @Test
    fun regularFileIdentityRejectsMultipleHardLinks() {
        val metadata = StorageMetadata(
            isDirectory = false,
            isRegularFile = true,
            ownerId = ownerId,
            permissions = 0x180,
            linkCount = 2,
        )

        assertFalse(metadata.hasOwnedRegularFileIdentity(ownerId))
        assertTrue(metadata.copy(linkCount = 1).hasOwnedRegularFileIdentity(ownerId))
        assertFalse(metadata.copy(linkCount = 1).hasOwnedRegularFileIdentity(ownerId + 1))
        assertFalse(
            metadata.copy(
                isDirectory = true,
                isRegularFile = false,
                linkCount = 1,
            ).hasOwnedRegularFileIdentity(ownerId),
        )
    }

    private companion object {
        const val ownerId = 10_123
        const val workerCount = 32
    }
}
