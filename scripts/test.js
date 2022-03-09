
console.log("Hi!");

hexo.extend.generator.register('hello', function (locals) {
    return {
        path: '404.html',
        layout: ['kar/404'],
        data: {
            top_img: false,
            aside: false,
            title: 'Page not found!',
        }
    }
})
