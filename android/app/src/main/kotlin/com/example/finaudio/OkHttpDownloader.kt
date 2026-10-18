package com.example.finaudio

import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.io.IOException
import java.util.concurrent.TimeUnit

class OkHttpDownloader(private val client: OkHttpClient) : Downloader() {

    override fun execute(request: Request): Response {
        val httpMethod = request.httpMethod()
        val url = request.url()
        val headers = request.headers()
        val dataToSend = request.dataToSend()

        val reqBuilder = okhttp3.Request.Builder().url(url)
        headers.forEach { (name, values) ->
            values.forEach { value ->
                reqBuilder.addHeader(name, value)
            }
        }

        if (headers["User-Agent"].isNullOrEmpty()) {
            reqBuilder.header(
                "User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:153.0) Gecko/20100101 Firefox/153.0"
            )
        }

        val body = if (dataToSend != null) {
            dataToSend.toRequestBody(null, 0, dataToSend.size)
        } else if (httpMethod == "POST") {
            ByteArray(0).toRequestBody(null, 0, 0)
        } else {
            null
        }

        reqBuilder.method(httpMethod, body)

        val call = client.newCall(reqBuilder.build())
        val okResponse = call.execute()

        val responseBody = okResponse.body?.string()
        val responseHeaders = okResponse.headers.toMultimap()

        return Response(
            okResponse.code,
            okResponse.message,
            responseHeaders,
            responseBody,
            okResponse.request.url.toString()
        )
    }

    companion object {
        val instance: OkHttpDownloader by lazy {
            val okHttpClient = OkHttpClient.Builder()
                .readTimeout(30, TimeUnit.SECONDS)
                .connectTimeout(15, TimeUnit.SECONDS)
                .build()
            OkHttpDownloader(okHttpClient)
        }
    }
}

